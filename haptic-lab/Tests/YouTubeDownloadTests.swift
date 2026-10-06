import XCTest
@testable import HapticLab

final class YouTubeDownloadTests: XCTestCase {
    func testRangesPreserveSignedQueryAndUseOnlyBoundedHTTPHeader() throws {
        let url = URL(string: "https://cdn.googlevideo.com/audio?sig=a%2Bb%2Fc%3D&clen=3000000&range=0-99")!
        let range = MusicDownloadRange(start: 1_048_576, end: 2_097_151, total: 3_000_000)
        let request = try range.request(for: url)
        XCTAssertTrue(request.url!.absoluteString.contains("sig=a%2Bb%2Fc%3D"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=1048576-2097151")
        XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "range" }.count, 0)
        XCTAssertEqual(range.count, YouTubeAudioDownload.chunkBytes)
    }

    func testResponsesRejectIgnoredRangesWrongOffsetsAndHTML() throws {
        let url = URL(string: "https://cdn.googlevideo.com/audio")!
        let range = MusicDownloadRange(start: 100, end: 199, total: 300)
        func response(_ status: Int, _ headers: [String: String]) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
        }
        XCTAssertNoThrow(try range.validate(response(206, ["Content-Range": "bytes 100-199/300", "Content-Length": "100"])))
        XCTAssertNoThrow(try range.validate(response(200, ["Content-Length": "100"])))
        XCTAssertThrowsError(try range.validate(response(200, ["Content-Length": "300"])))
        XCTAssertThrowsError(try range.validate(response(206, ["Content-Range": "bytes 0-99/300", "Content-Length": "100"])))
        XCTAssertThrowsError(try range.validate(response(206, [:])))
        XCTAssertThrowsError(try range.validate(response(200, ["Content-Length": "100", "Content-Type": "text/html"])))
        XCTAssertThrowsError(try range.validate(response(403, [:])))
        XCTAssertFalse(YouTubeAudioDownload.isYouTubeAudio(URL(string: "https://googlevideo.com.evil.example/audio")!))
    }

    func testChunksJoinInOrderWithoutRepeatingBytesOrLosingFinalPartialChunk() async throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: destination) }
        let payload = Data((0..<(Int(YouTubeAudioDownload.chunkBytes) * 2 + 17)).map { UInt8($0 % 251) })
        let recorder = RangeRecorder()
        let result = try await YouTubeAudioDownload.download(URL(string: "https://cdn.googlevideo.com/audio?clen=\(payload.count)")!, to: destination, progress: { _, _ in }, fetch: { request, range, received in
            await recorder.add(range)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Range"), "bytes=\(range.start)-\(range.end)")
            let data = payload.subdata(in: Int(range.start)..<(Int(range.end) + 1))
            received(Int64(data.count))
            return data
        })
        XCTAssertEqual(result, destination)
        XCTAssertEqual(try Data(contentsOf: result), payload)
        let ranges = await recorder.ranges
        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(ranges.last?.count, 17)
        XCTAssertEqual(ranges[1].start, ranges[0].end + 1)
    }

    func testFailedOrCancelledChunkDeletesPartialAudio() async throws {
        for cancel in [false, true] {
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            let url = URL(string: "https://cdn.googlevideo.com/audio?clen=\(YouTubeAudioDownload.chunkBytes + 1)")!
            do {
                _ = try await YouTubeAudioDownload.download(url, to: destination, progress: { _, _ in }, fetch: { _, range, _ in
                    if range.start == 0 { return Data(repeating: 1, count: Int(range.count)) }
                    if cancel { throw CancellationError() }
                    throw MusicError.network("中断")
                })
                XCTFail("Incomplete downloads must not succeed")
            } catch { XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path)) }
        }
    }

    func testCancellingTaskDuringDownloadRemovesItsWorkingAudio() async throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        let task = Task {
            try await YouTubeAudioDownload.download(URL(string: "https://cdn.googlevideo.com/audio?clen=100")!, to: destination, progress: { _, _ in }, fetch: { _, _, _ in
                try await Task.sleep(nanoseconds: 60_000_000_000)
                return Data(repeating: 0, count: 100)
            })
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled downloads must not succeed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}

private actor RangeRecorder {
    var ranges: [MusicDownloadRange] = []
    func add(_ range: MusicDownloadRange) { ranges.append(range) }
}
