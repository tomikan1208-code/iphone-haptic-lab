import XCTest
@testable import HapticLab

final class MusicVariantTests: XCTestCase {
    private func track(style: MusicGenerationStyle = .following, profile: MusicArrangement = .standard, duration: Double = 8) -> MusicHapticTrack {
        MusicHapticTrack(version: 1, audioSHA256: String(repeating: "a", count: 64), duration: duration,
            envelope: [0.0, duration].map { .init(time: $0, bass: 0.5, energy: 0.5, sharpness: 0.3) }, taps: [],
            analysis: .init(engine: "pc", elapsedSeconds: 1, sampleRate: 44_100,
                            hopMilliseconds: 10, fftSize: 4_096, style: style, profile: profile))
    }

    @MainActor private func wait(_ library: MusicLibrary) async throws {
        let deadline = Date().addingTimeInterval(5)
        while library.preparation != nil, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNil(library.preparation, library.message ?? "Preparation did not finish")
    }

    @MainActor
    func testLegacySingleResultMigratesWithoutLosingTrackSettingsOrMedia() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = MusicLibraryDisk(root: root)
        try disk.initialize()
        var record = MusicRecord(selection: try MusicSelection.youtube(id: "lkiV3U0GfGg"))
        record.trackFilename = "legacy.json"
        record.mediaFilename = "source.wav"
        record.settings.gain = 1.5
        try JSONEncoder().encode(track()).write(to: disk.tracks.appendingPathComponent("legacy.json"))
        try Data([1,2,3]).write(to: disk.media.appendingPathComponent("source.wav"))
        try disk.write([record])
        let library = MusicLibrary(root: root)
        let loaded = try XCTUnwrap(library.prepared.first)
        XCTAssertEqual(loaded.analysisVariants.count, 1)
        XCTAssertEqual(loaded.selectedVariantID, "legacy.json")
        XCTAssertEqual(library.settings(for: loaded.id).gain, 1.5)
        XCTAssertEqual(try library.disk.track(loaded), track())
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(library.disk.mediaURL(loaded)).path))
        try library.selectVariant("legacy.json", for: loaded.id)
        XCTAssertEqual(MusicLibrary(root: root).prepared.first?.selectedVariantID, "legacy.json")
    }

    @MainActor
    func testAddingComparisonsPreservesPriorResultsLastSelectionAndDeletesOnlySelectedResults() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = track()
        var services = MusicPreparationServices()
        services.analyzeOnPC = { _, _, _, style, profile, _ in
            var result = expected
            result.analysis?.style = style
            result.analysis?.profile = profile
            return result
        }
        let library = MusicLibrary(root: root, services: services)
        let selection = try MusicSelection.youtube(id: "lkiV3U0GfGg")
        let connection = try PCServerConnection(address: "http://127.0.0.1:8765", token: String(repeating: "a", count: 32))
        for style in [MusicGenerationStyle.following, .musical, .arranged] {
            library.prepare(selection, style: style, connection: connection)
            try await wait(library)
        }
        let record = try XCTUnwrap(library.record(for: selection))
        let variants = record.analysisVariants
        XCTAssertEqual(variants.count, 3)
        XCTAssertEqual(Set(variants.map(\.trackFilename)).count, 3)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.disk.tracks.path).count, 3)
        library.saveSettings(MusicSettings(gain: 1.2), id: selection.id)
        try library.selectVariant(variants[0].id, for: selection.id)
        let restored = MusicLibrary(root: root)
        XCTAssertEqual(restored.prepared.first?.selectedVariantID, variants[0].id)
        XCTAssertEqual(try restored.disk.track(XCTUnwrap(restored.prepared.first)), expected)
        XCTAssertEqual(restored.settings(for: selection.id).gain, 1.2)
        try restored.deleteVariants([variants[0].id, variants[2].id], for: selection.id)
        let remaining = try XCTUnwrap(restored.record(for: selection))
        XCTAssertEqual(remaining.analysisVariants.map(\.id), [variants[1].id])
        XCTAssertEqual(remaining.selectedVariantID, variants[1].id)
        XCTAssertEqual(restored.settings(for: selection.id).gain, 1.2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: restored.disk.tracks.path), [variants[1].trackFilename])
        try restored.deleteVariants([variants[1].id], for: selection.id)
        XCTAssertTrue(restored.records.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: restored.disk.tracks.path).isEmpty)
    }

    @MainActor
    func testDeletingOneComparisonKeepsSharedAudioForOtherResults() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try XCTUnwrap(Bundle.main.url(forResource: "MusicDemo", withExtension: "wav"))
        let expected = track(duration: 12)
        var services = MusicPreparationServices()
        services.analyzeOnPC = { _, _, _, _, _, _ in expected }
        let library = MusicLibrary(root: root, services: services)
        let selection = MusicSelection.file(source)
        let connection = try PCServerConnection(address: "http://127.0.0.1:8765", token: String(repeating: "a", count: 32))
        for _ in 0..<2 {
            library.prepare(selection, audioFile: source, connection: connection)
            try await wait(library)
        }
        let record = try XCTUnwrap(library.record(for: selection))
        XCTAssertEqual(record.analysisVariants.count, 2)
        XCTAssertEqual(Set(record.analysisVariants.compactMap(\.mediaFilename)).count, 1)
        let audio = try XCTUnwrap(library.disk.mediaURL(record))
        try library.deleteVariants([record.analysisVariants[0].id], for: selection.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.disk.media.path).count, 1)
    }

    @MainActor
    func testFailedSelectionOrDeletionWriteKeepsBothSavedResults() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = MusicLibraryDisk(root: root)
        try disk.initialize()
        var record = MusicRecord(selection: try MusicSelection.youtube(id: "lkiV3U0GfGg"))
        let variants = ["first", "second"].map { MusicAnalysisVariant(id: $0, createdAt: Date(), trackFilename: "\($0).json", trackBytes: 1) }
        record.variants = variants
        record.useVariant(variants[0])
        for variant in variants { try JSONEncoder().encode(track()).write(to: disk.tracks.appendingPathComponent(variant.trackFilename)) }
        try disk.write([record])
        let library = MusicLibrary(root: root)
        try FileManager.default.removeItem(at: disk.index)
        try FileManager.default.createDirectory(at: disk.index, withIntermediateDirectories: false)
        XCTAssertThrowsError(try library.selectVariant(variants[1].id, for: record.id))
        XCTAssertThrowsError(try library.deleteVariants([variants[0].id], for: record.id))
        XCTAssertEqual(library.records.first?.selectedVariantID, variants[0].id)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: disk.tracks.path).count, 2)
    }

    @MainActor
    func testSwitchingAnalysisKeepsPlayingPositionAndMediaClock() throws {
        let playback = MusicPlayback()
        let selection = try MusicSelection.youtube(id: "lkiV3U0GfGg")
        playback.load(selection, track: track(), mediaURL: nil, settings: .init(), variantID: "old")
        playback.receiveYouTube(["state":1, "videoID":"lkiV3U0GfGg", "duration":8.0, "time":2.0,
                                 "rate":1.0, "sent":Date().timeIntervalSince1970 * 1_000], videoID: "lkiV3U0GfGg")
        XCTAssertTrue(playback.isPlaying)
        let item = playback.player.currentItem
        try playback.switchAnalysis(track(style: .musical), variantID: "new")
        XCTAssertEqual(playback.position, 2)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertTrue(playback.player.currentItem === item)
        XCTAssertEqual(playback.analysisVariantID, "new")
        XCTAssertEqual(playback.visualizationTrack?.analysis?.style, .musical)
        playback.stop()
    }
}
