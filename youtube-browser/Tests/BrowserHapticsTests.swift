import XCTest
import QuartzCore
@testable import ResonWeb

@MainActor
private final class RecordingRenderer: BrowserHapticRendering {
    var supported = true
    var settings = MusicSettings()
    var onFailure: ((String) -> Void)?
    var positions: [Double] = []
    var rates: [Double] = []
    var lastClock: Double?
    var rendering = false
    var suspended = false
    func synchronize(track: MusicHapticTrack?, position: Double, playing: Bool, rate: Double, clockPosition: Double?) {
        rendering = track != nil && playing
        positions.append(position); rates.append(rate); lastClock = clockPosition
    }
    func stop() { rendering = false }
    func suspend() { suspended = true; stop() }
}

final class BrowserHapticsTests: XCTestCase {
    @MainActor
    private func setup(prepared: Bool = true) throws -> (MusicLibrary, BrowserHaptics, RecordingRenderer, URL, UserDefaults) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let disk = MusicLibraryDisk(root: root)
        try disk.initialize()
        if prepared {
            let filename = UUID().uuidString + ".json"
            try JSONEncoder().encode(BrowserFixtures.track()).write(to: disk.tracks.appendingPathComponent(filename))
            var record = MusicRecord(selection: try MusicSelection.youtube(id: BrowserFixtures.firstID, title: "テスト動画"))
            record.trackFilename = filename
            try disk.write([record])
        }
        let library = MusicLibrary(root: root)
        let suite = "BrowserHapticsTests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let renderer = RecordingRenderer()
        return (library, BrowserHaptics(library: library, renderer: renderer, defaults: defaults), renderer, root, defaults)
    }

    private func sample(position: Double = 10, id: String = BrowserFixtures.firstID, duration: Double = 60,
                        rate: Double = 1, paused: Bool = false, seeking: Bool = false, buffering: Bool = false,
                        advertisement: Bool = false, ready: Bool = true, hidden: Bool = false) -> WebPlaybackSnapshot {
        WebPlaybackSnapshot(url: URL(string: "https://www.youtube.com/watch?v=\(id)")!, videoID: id, title: "テスト動画", artist: "",
            position: position, duration: duration, rate: rate, sent: Date().timeIntervalSince1970 * 1_000,
            paused: paused, ended: false, seeking: seeking, ready: ready, buffering: buffering,
            advertisement: advertisement, hidden: hidden)
    }

    @MainActor func testPreparedTrackAutomaticallyFollowsWebsiteClockAndSpeed() throws {
        let (_, haptics, renderer, _, _) = try setup()
        haptics.receive(sample())
        XCTAssertTrue(renderer.rendering)
        XCTAssertTrue(haptics.isSynchronizing)
        XCTAssertEqual(renderer.lastClock, 10)
        XCTAssertEqual(renderer.positions.last!, 10, accuracy: 0.05)
        haptics.receive(sample(position: 20, rate: 1.5))
        XCTAssertEqual(renderer.rates.last, 1.5)
        XCTAssertEqual(renderer.lastClock, 20)
    }
    @MainActor func testPauseSeekingBufferingHiddenAndAdStopThenFreshPlaybackResumes() throws {
        let (_, haptics, renderer, _, _) = try setup()
        for blocked in [sample(paused: true), sample(seeking: true), sample(buffering: true),
                        sample(advertisement: true), sample(ready: false), sample(hidden: true)] {
            haptics.receive(sample())
            XCTAssertTrue(renderer.rendering)
            haptics.receive(blocked)
            XCTAssertFalse(renderer.rendering)
            XCTAssertFalse(haptics.isSynchronizing)
            haptics.receive(sample(position: 25))
            XCTAssertTrue(renderer.rendering)
            XCTAssertEqual(renderer.lastClock, 25)
        }
    }
    @MainActor func testAdDurationCannotReplaceSelectedVideoDuration() throws {
        let (_, haptics, renderer, _, _) = try setup()
        haptics.receive(sample(duration: 15, advertisement: true))
        XCTAssertEqual(haptics.status, .advertisement)
        XCTAssertNil(haptics.selection?.duration)
        XCTAssertFalse(renderer.rendering)
        haptics.receive(sample())
        XCTAssertTrue(renderer.rendering)
        XCTAssertEqual(haptics.selection?.duration, 60)
    }
    @MainActor func testUnpreparedAndChangedVideoNeverUseOldTrackOrStartAnalysis() throws {
        let (library, haptics, renderer, _, _) = try setup()
        haptics.receive(sample())
        XCTAssertTrue(renderer.rendering)
        haptics.receive(sample(id: BrowserFixtures.nextID))
        XCTAssertFalse(renderer.rendering)
        XCTAssertEqual(haptics.status, .needsPreparation)
        XCTAssertNil(library.preparation)
        haptics.receive(sample())
        XCTAssertTrue(renderer.rendering)
    }
    @MainActor func testDurationMismatchWaitsForStableClockAndStopsImmediately() throws {
        let (_, haptics, renderer, _, _) = try setup()
        let host = CACurrentMediaTime()
        haptics.receive(sample())
        haptics.receive(sample(duration: 100), hostTime: host)
        XCTAssertFalse(renderer.rendering)
        XCTAssertEqual(haptics.status, .waiting)
        haptics.receive(sample(duration: 100), hostTime: host + 1.1)
        XCTAssertEqual(haptics.status, .mismatch)
        haptics.receive(sample(duration: 100, paused: true), hostTime: host + 1.2)
        haptics.receive(sample(duration: 100), hostTime: host + 1.3)
        XCTAssertEqual(haptics.status, .waiting)
        haptics.receive(sample(), hostTime: host + 1.4)
        XCTAssertTrue(renderer.rendering)
    }
    @MainActor func testBackgroundAndDisconnectCannotResumeOldSamples() throws {
        let (_, haptics, renderer, _, _) = try setup()
        haptics.receive(sample())
        haptics.setForeground(false)
        XCTAssertTrue(renderer.suspended)
        XCTAssertFalse(renderer.rendering)
        haptics.setForeground(true)
        XCTAssertFalse(renderer.rendering)
        haptics.receive(sample(position: 30))
        XCTAssertTrue(renderer.rendering)
        haptics.disconnect()
        XCTAssertFalse(renderer.rendering)
        XCTAssertNil(haptics.selection)
        haptics.refreshPreparedTrack()
        XCTAssertFalse(renderer.rendering)
    }
    @MainActor func testDisabledStatePersistsAndDoesNotStopWebsitePlayback() throws {
        let (library, haptics, renderer, _, defaults) = try setup()
        haptics.receive(sample())
        haptics.enabled = false
        XCTAssertFalse(renderer.rendering)
        XCTAssertTrue(haptics.videoPlaying)
        XCTAssertFalse(BrowserHaptics(library: library, renderer: RecordingRenderer(), defaults: defaults).enabled)
        haptics.enabled = true
        XCTAssertTrue(renderer.rendering)
    }
    @MainActor func testIndependentAdjustmentsPersistAndUpdateRenderer() throws {
        let (library, haptics, renderer, root, _) = try setup()
        haptics.receive(sample())
        var settings = MusicSettings()
        settings.emphasizeTaps()
        settings.offset = 0.12
        haptics.saveSettings(settings)
        XCTAssertEqual(renderer.settings.continuousGain, 0.25)
        XCTAssertEqual(renderer.settings.transientGain, 1)
        XCTAssertEqual(renderer.settings.transientSharpness, 0.9)
        XCTAssertEqual(renderer.settings.density, 1)
        XCTAssertEqual(renderer.settings.offset, 0.12)
        let reopened = MusicLibrary(root: root)
        XCTAssertEqual(reopened.settings(for: "youtube-" + BrowserFixtures.firstID), settings)
        XCTAssertTrue(reopened.prepared[0].hasIndividualSettings)
        library.resetSettingsToGlobal(id: "youtube-" + BrowserFixtures.firstID)
        haptics.refreshPreparedTrack()
        XCTAssertEqual(renderer.settings, library.globalSettings)
    }
    @MainActor func testPCPreparationSavesReusableVariantsWithoutMediaAndCancellationKeepsSavedTrack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var services = MusicPreparationServices()
        services.analyzeOnPC = { _, _, _, _, _, progress in
            progress(0.5, "解析中")
            try await Task.sleep(nanoseconds: 100_000_000)
            return BrowserFixtures.track()
        }
        let library = MusicLibrary(root: root, services: services)
        let selection = try MusicSelection.youtube(id: BrowserFixtures.firstID)
        let connection = try PCServerConnection(address: "http://192.168.1.2:8765", token: String(repeating: "a", count: 32))
        for _ in 0..<2 {
            library.prepare(selection, audioFile: nil, method: .pc, style: .arranged, profile: .standard, connection: connection)
            for _ in 0..<200 where library.preparation != nil { try await Task.sleep(nanoseconds: 20_000_000) }
            XCTAssertNil(library.preparation)
        }
        let record = try XCTUnwrap(library.record(for: selection))
        XCTAssertEqual(record.analysisVariants.count, 2)
        XCTAssertNil(record.mediaFilename)
        XCTAssertEqual(try library.disk.track(record).duration, 60)
        library.prepare(selection, audioFile: nil, method: .pc, connection: connection)
        library.cancelPreparation()
        XCTAssertEqual(library.record(for: selection)?.analysisVariants.count, 2)
        let oldID = record.analysisVariants[0].id
        _ = try library.selectVariant(oldID, for: selection.id)
        XCTAssertEqual(MusicLibrary(root: root).prepared[0].selectedVariantID, oldID)
    }
}
