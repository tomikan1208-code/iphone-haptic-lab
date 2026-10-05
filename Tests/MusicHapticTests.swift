import XCTest
@testable import HapticLab

final class MusicHapticTests: XCTestCase {
    private let videoID = "dQw4w9WgXcQ"

    func testYouTubeURLsHaveOneCanonicalCacheIdentity() throws {
        let urls = ["https://www.youtube.com/watch?v=\(videoID)&list=PLtest&t=30",
                    "https://youtu.be/\(videoID)?si=test", "https://m.youtube.com/shorts/\(videoID)",
                    "https://music.youtube.com/watch?v=\(videoID)"]
        for url in urls {
            let selection = try MusicSelection.parse(url)
            XCTAssertEqual(selection.videoID, videoID)
            XCTAssertEqual(selection.id, "youtube-\(videoID)")
            XCTAssertEqual(selection.url, "https://www.youtube.com/watch?v=\(videoID)")
        }
    }

    func testURLParserRejectsPhishingScriptsInvalidIDsAndPlaylistOnlyLinks() {
        for input in ["javascript:alert(1)", "https://youtube.com.evil.example/watch?v=\(videoID)",
                      "https://youtube.com@evil.example/watch?v=\(videoID)", "https://youtu.be/short",
                      "https://youtube.com/playlist?list=PLtest", "https://example.com/live.m3u8", "file:///test.mp3"] {
            XCTAssertThrowsError(try MusicSelection.parse(input), input)
        }
    }

    func testRemoteIdentityPreservesSignedQueryAndDropsFragment() throws {
        let result = try MusicSelection.parse("https://example.com/music.m4a?signature=a%2Bb#section")
        XCTAssertEqual(result.kind, .remote)
        XCTAssertEqual(result.url, "https://example.com/music.m4a?signature=a%2Bb")
    }

    func testChunkBoundaryDoesNotRepeatTapsAndUsesIndependentCurves() throws {
        let track = fixture(taps: [.init(time: 0.6, intensity: 0.8, sharpness: 0.7)])
        let before = track.segment(at: 0, length: 0.6)
        let after = track.segment(at: 0.6, length: 0.6)
        XCTAssertFalse(before.contains { $0.id == "music-taps" })
        let taps = try XCTUnwrap(after.first { $0.id == "music-taps" })
        XCTAssertEqual(taps.events.count, 1)
        XCTAssertEqual(taps.events[0].time, 0)
        XCTAssertTrue(taps.curves.isEmpty)
        for pattern in before + after { XCTAssertNoThrow(try pattern.validated()) }
    }

    func testRateAndMidSegmentSeekKeepEnvelopeAndEventTimesValid() throws {
        let track = fixture(taps: [.init(time: 0.8, intensity: 0.8, sharpness: 0.5)])
        for rate in [0.25, 1, 2] {
            for pattern in track.segment(at: 0.7, length: 0.5, rate: rate) {
                XCTAssertNoThrow(try pattern.validated())
                XCTAssertEqual(pattern.duration, 0.5 / rate, accuracy: 0.000_001)
                if let tap = pattern.events.first(where: { $0.kind == .tap }) { XCTAssertEqual(tap.time, 0.1 / rate, accuracy: 0.000_001) }
            }
        }
        XCTAssertTrue(track.segment(at: -1, length: 1).isEmpty)
        XCTAssertTrue(track.segment(at: 1.2, length: 1).isEmpty)
    }

    func testSilenceCreatesNoHapticPatternsAndCorruptionIsRejected() throws {
        let silent = fixture(level: 0)
        XCTAssertTrue(silent.segment(at: 0, length: 0.6).isEmpty)
        let invalid = MusicHapticTrack(version: 9, audioSHA256: String(repeating: "a", count: 64),
                                      duration: 1.2, envelope: silent.envelope, taps: [])
        XCTAssertThrowsError(try invalid.validated())
        XCTAssertFalse(MusicLibraryDisk.safeFilename("../../library.json"))
        XCTAssertFalse(MusicLibraryDisk.safeFilename("/other/source.wav"))
    }

    func testSignalExtractorRejectsSilentAudio() throws {
        let extractor = try MusicSignalExtractor(channels: 1)
        try extractor.append(Array(repeating: 0, count: 22_050))
        XCTAssertThrowsError(try extractor.finish(hash: String(repeating: "a", count: 64)))
    }

    func testOppositePhaseStereoPreservesBassEnergy() throws {
        let mono = try MusicSignalExtractor(channels: 1)
        let stereo = try MusicSignalExtractor(channels: 2)
        let samples = (0..<22_050).map { Float(sin(Double($0) * .pi * 2 * 80 / 22_050) * 0.4) }
        try mono.append(samples)
        try stereo.append(samples.flatMap { [$0, -$0] })
        let a = try mono.finish(hash: String(repeating: "a", count: 64))
        let b = try stereo.finish(hash: String(repeating: "b", count: 64))
        XCTAssertGreaterThan(b.envelope.map(\.bass).max() ?? 0, 0.9)
        XCTAssertEqual(a.envelope[20].bass, b.envelope[20].bass, accuracy: 0.000_1)
    }

    func testKnownPercussionOnsetsAreDetectedNearTheirMediaTimes() throws {
        let extractor = try MusicSignalExtractor(channels: 1)
        let samples = (0..<33_075).map { index -> Float in
            let time = Double(index) / 22_050
            for onset in [0.5, 1.0] where time >= onset && time < onset + 0.05 {
                return Float(sin((time - onset) * .pi * 2 * 150) * exp(-(time - onset) * 60) * 0.8)
            }
            return 0
        }
        try extractor.append(samples)
        let track = try extractor.finish(hash: String(repeating: "a", count: 64))
        for onset in [0.5, 1.0] {
            XCTAssertTrue(track.taps.contains { abs($0.time - onset) < 0.08 }, "Missing onset at \(onset)")
        }
        XCTAssertTrue(track.envelope.filter { $0.time < 0.4 }.allSatisfy { $0.energy == 0 && $0.bass == 0 })
    }

    @MainActor
    func testRealAudioAnalysisCacheReloadAndIndividualDeletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = MusicLibrary(root: root)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "MusicDemo", withExtension: "wav"))
        let selection = MusicSelection.file(url)
        library.prepare(selection, audioFile: url)
        let deadline = Date().addingTimeInterval(30)
        while library.preparation != nil, Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertNil(library.preparation)
        let record = try XCTUnwrap(library.prepared.first, library.message ?? "No generated track")
        let track = try library.disk.track(record)
        XCTAssertEqual(track.duration, 12, accuracy: 0.02)
        XCTAssertGreaterThan(track.taps.count, 10)
        XCTAssertGreaterThan(record.trackBytes, 0)
        library.saveHistory(selection)
        library.saveSettings(MusicSettings(mode: .beats, gain: 0.25), id: record.id)
        let reloaded = MusicLibrary(root: root)
        XCTAssertEqual(reloaded.prepared.count, 1)
        XCTAssertEqual(reloaded.history.count, 1)
        XCTAssertEqual(reloaded.records[0].settings.gain, 0.25)
        XCTAssertEqual(try reloaded.disk.track(reloaded.records[0]), track)
        let mediaURL = try XCTUnwrap(reloaded.disk.mediaURL(record))
        let trackURL = reloaded.disk.tracks.appendingPathComponent(try XCTUnwrap(record.trackFilename))
        try reloaded.delete(reloaded.records[0])
        XCTAssertTrue(reloaded.records.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trackURL.path))
        XCTAssertTrue(MusicLibrary(root: root).records.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testCanceledGenerationDoesNotPublishOrLeavePartialData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = MusicLibrary(root: root)
        let url = try XCTUnwrap(Bundle.main.url(forResource: "MusicDemo", withExtension: "wav"))
        library.prepare(MusicSelection.file(url), audioFile: url)
        library.cancelPreparation()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertTrue(library.records.isEmpty)
        XCTAssertNil(library.preparation)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: library.disk.tracks.path).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: library.disk.working.path).isEmpty)
    }

    private func fixture(level: Double = 0.8, taps: [MusicTap] = []) -> MusicHapticTrack {
        MusicHapticTrack(version: 1, audioSHA256: String(repeating: "a", count: 64), duration: 1.2,
            envelope: [0.0, 0.6, 1.2].map { .init(time: $0, bass: level, energy: level, sharpness: 0.3) }, taps: taps)
    }
}
