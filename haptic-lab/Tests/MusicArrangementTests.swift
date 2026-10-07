import XCTest
@testable import HapticLab

final class MusicArrangementTests: XCTestCase {
    @MainActor
    func testDefaultYouTubePreparationUsesPCAndPersistsArrangedTrack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let score = MusicArrangementScore(version: 1, sections: [
            .init(id: "s0", start: 0, end: 1, label: "chorus", confidence: 0.8, mood: "driving", family: "drive")
        ], bars: [], rhythmAgreement: 1, rhythmSource: "beat-this")
        let expected = MusicHapticTrack(version: 3, audioSHA256: String(repeating: "a", count: 64), duration: 1,
            envelope: [.init(time: 0, bass: 0.5, energy: 0.5, sharpness: 0.2, intensity: 0.1),
                       .init(time: 1, bass: 0, energy: 0, sharpness: 0.2, intensity: 0)],
            taps: [], arrangement: score)
        var services = MusicPreparationServices()
        services.youtubeAudioURL = { _ in
            XCTFail("New preparation must send the video ID to PC")
            throw MusicError.unsupportedMedia
        }
        services.analyzeOnPC = { _, selection, file, style, profile, _ in
            XCTAssertEqual(selection.videoID, "dQw4w9WgXcQ")
            XCTAssertNil(file)
            XCTAssertEqual(style, .arranged)
            XCTAssertEqual(profile, .standard)
            return expected
        }
        let library = MusicLibrary(root: root, services: services)
        let selection = try MusicSelection.youtube(id: "dQw4w9WgXcQ")
        let connection = try PCServerConnection(address: "http://127.0.0.1:8765", token: String(repeating: "a", count: 32))
        library.prepare(selection, connection: connection)
        let deadline = Date().addingTimeInterval(10)
        while library.preparation != nil, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertNil(library.preparation)
        let record = try XCTUnwrap(library.record(for: selection), library.message ?? "Missing PC track")
        XCTAssertEqual(try library.disk.track(record), expected)
        XCTAssertNil(record.mediaFilename)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: library.disk.working.path).isEmpty)
        let restored = MusicLibrary(root: root)
        XCTAssertEqual(try restored.disk.track(XCTUnwrap(restored.record(for: selection))), expected)
    }

    func testComposedIntensityIsPlayedDirectlyAndBedCurveDoesNotScaleAccent() throws {
        let sections = [MusicArrangementScore.Section(id: "s0", start: 0, end: 1, label: "chorus",
                                                      confidence: 0.8, mood: "driving", family: "drive")]
        let score = MusicArrangementScore(version: 1, sections: sections, bars: [],
                                           rhythmAgreement: 0.9, rhythmSource: "beat-this")
        let track = MusicHapticTrack(version: 3, audioSHA256: String(repeating: "a", count: 64), duration: 1,
            envelope: [
                .init(time: 0, bass: 1, energy: 1, sharpness: 0.2, mid: 1, intensity: 0.1),
                .init(time: 1, bass: 1, energy: 1, sharpness: 0.2, mid: 1, intensity: 0.3)
            ], taps: [.init(time: 0.5, intensity: 0.6, sharpness: 0.9, role: "accent", priority: 1)],
            arrangement: score)
        XCTAssertNoThrow(try track.validated())
        let settings = MusicSettings(gain: 1, bass: 0, density: 0)
        XCTAssertEqual(track.output(at: 0.5, settings: settings).continuous, 0.2, accuracy: 0.000001)
        XCTAssertEqual(track.output(at: 0.5, settings: settings).transient, 0.6, accuracy: 0.000001)
        let layers = track.segment(at: 0.25, length: 0.5, settings: settings)
        XCTAssertEqual(layers.count, 2)
        let accents = try XCTUnwrap(layers.first(where: { $0.id == "music-taps" }))
        XCTAssertTrue(accents.curves.isEmpty)
        XCTAssertEqual(accents.events.first?.intensity, 0.6)
        let roundTrip = try JSONDecoder().decode(MusicHapticTrack.self, from: JSONEncoder().encode(track))
        XCTAssertEqual(try roundTrip.validated(), track)
    }

    func testVersionThreeCannotSilentlyFallBackToLegacyBassMapping() {
        let invalid = MusicHapticTrack(version: 3, audioSHA256: String(repeating: "a", count: 64), duration: 1,
            envelope: [.init(time: 0, bass: 1, energy: 1, sharpness: 0.5)], taps: [])
        XCTAssertThrowsError(try invalid.validated())
    }
}
