import XCTest
import AVFoundation
@testable import HapticLab

final class YouTubeMediaTests: XCTestCase {
    func testSearchParsesEscapedTitlesDeduplicatesAndIgnoresAdsAndLiveVideos() throws {
        let video: [String: Any] = ["videoId": "dQw4w9WgXcQ", "title": ["runs": [["text": "曲 {live} \"demo\""]]],
                                    "ownerText": ["runs": [["text": "アーティスト"]]], "lengthText": ["simpleText": "3:42"]]
        let live: [String: Any] = ["videoId": "BaW_jenozKc", "badges": [["metadataBadgeRenderer": ["style": "BADGE_STYLE_TYPE_LIVE_NOW"]]]]
        let rows: [[String: Any]] = [["videoRenderer": video], ["videoRenderer": video], ["videoRenderer": live],
                                     ["adSlotRenderer": ["videoRenderer": ["videoId": "abcdefghijk"]]]]
        let section: [String: Any] = ["itemSectionRenderer": ["contents": rows]]
        let primary: [String: Any] = ["sectionListRenderer": ["contents": [section]]]
        let contents: [String: Any] = ["contents": ["twoColumnSearchResultsRenderer": ["primaryContents": primary]]]
        let data = try JSONSerialization.data(withJSONObject: contents)
        let html = "<script>var ytInitialData = \(String(decoding: data, as: UTF8.self));</script>"
        let results = try YouTubeSearchService.parse(html)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "曲 {live} \"demo\"")
        XCTAssertEqual(results[0].artist, "アーティスト")
        XCTAssertEqual(results[0].duration, 222)
        XCTAssertEqual(results[0].id, "youtube-dQw4w9WgXcQ")
        XCTAssertThrowsError(try YouTubeSearchService.parse("<html>consent</html>"))
        XCTAssertEqual(try YouTubeSearchService.initialData(in: "window[\"ytInitialData\"] = \(String(decoding: data, as: UTF8.self));"), data)
    }

    @MainActor
    func testVideoPreparationPersistsSpectrumDeletesAudioAndSurvivesRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let demo = try XCTUnwrap(Bundle.main.url(forResource: "MusicDemo", withExtension: "wav"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audio = root.appendingPathComponent("fixture.m4a")
        let exporter = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: demo), presetName: AVAssetExportPresetAppleM4A))
        exporter.outputURL = audio
        exporter.outputFileType = .m4a
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously { continuation.resume() }
        }
        XCTAssertEqual(exporter.status, .completed)
        var services = MusicPreparationServices()
        services.youtubeAudioURL = { selection in
            XCTAssertEqual(selection.videoID, "dQw4w9WgXcQ")
            return URL(string: "https://test.googlevideo.com/audio")!
        }
        services.download = { _, destination, _ in
            try FileManager.default.copyItem(at: audio, to: destination)
            return destination
        }
        let library = MusicLibrary(root: root, services: services)
        var selection = try MusicSelection.youtube(id: "dQw4w9WgXcQ", title: "テスト動画")
        selection.duration = 12
        library.prepare(selection, method: .device, style: .following)
        try await waitForPreparation(library)
        let record = try XCTUnwrap(library.record(for: selection))
        XCTAssertTrue(record.isPrepared)
        XCTAssertNil(record.mediaFilename)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: library.disk.working.path).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: library.disk.media.path).isEmpty)
        let track = try library.disk.track(record)
        XCTAssertEqual(track.duration, 12, accuracy: 0.1)
        XCTAssertEqual(track.version, 2)
        XCTAssertEqual(track.spectrum?.first?.levels.count, 24)
        XCTAssertGreaterThan(track.spectrum?.count ?? 0, 500)
        let restored = MusicLibrary(root: root)
        XCTAssertEqual(try restored.disk.track(XCTUnwrap(restored.record(for: selection))), track)
    }

    @MainActor
    func testFailedVideoDownloadRemovesPartialAudioAndDoesNotPublish() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var services = MusicPreparationServices()
        services.youtubeAudioURL = { _ in URL(string: "https://test.googlevideo.com/audio")! }
        services.download = { _, destination, _ in
            try Data("partial audio".utf8).write(to: destination)
            throw MusicError.network("取得失敗")
        }
        let library = MusicLibrary(root: root, services: services)
        library.prepare(try MusicSelection.youtube(id: "dQw4w9WgXcQ"), method: .device, style: .following)
        try await waitForPreparation(library)
        XCTAssertTrue(library.records.isEmpty)
        XCTAssertEqual(library.message, "取得失敗")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: library.disk.working.path).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: library.disk.tracks.path).isEmpty)
    }

    @MainActor private func waitForPreparation(_ library: MusicLibrary) async throws {
        for _ in 0..<1_000 {
            if library.preparation == nil { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Preparation did not finish")
    }
}
