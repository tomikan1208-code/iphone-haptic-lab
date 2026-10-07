import XCTest
@testable import HapticLab

final class MusicArrangementTests: XCTestCase {
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
