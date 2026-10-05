import XCTest
@testable import HapticLab

final class HapticPatternTests: XCTestCase {
    func testQuickPlayUsesPersistedValuesAndUsefulDefaults() throws {
        let suite = "HapticLabTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = ExperimentConfiguration.saved(defaults: defaults)
        XCTAssertEqual(initial.intensity, 0.65)
        XCTAssertEqual(initial.duration, 1.5)
        defaults.set("pulses", forKey: "experiment.kind")
        defaults.set(0.28, forKey: "experiment.intensity")
        defaults.set(0.4, forKey: "experiment.duration")
        let pattern = PatternFactory.experiment(.saved(defaults: defaults))
        XCTAssertNoThrow(try pattern.validated())
        XCTAssertEqual(pattern.events.count, 2)
        XCTAssertEqual(pattern.events.first?.intensity, 0.28)
    }

    func testBundledCatalogHasUniqueValidPatterns() throws {
        let patterns = try PatternCatalog.load()
        XCTAssertEqual(patterns.count, 10)
        XCTAssertEqual(Set(patterns.map(\.id)).count, patterns.count)
        XCTAssertTrue(patterns.contains { !$0.curves.isEmpty })
        XCTAssertTrue(patterns.contains { $0.category == "rhythm" })
        for pattern in patterns { XCTAssertNoThrow(try pattern.validated()) }
    }

    func testInvalidHardwareParametersAreRejected() {
        for invalid in [-0.01, 1.01, .nan, .infinity] {
            let event = HapticEventSpec(kind: .continuous, time: 0, duration: 1,
                                        intensity: invalid, sharpness: 0.5)
            XCTAssertThrowsError(try spec(events: [event]).validated())
        }
        let overlong = HapticEventSpec(kind: .continuous, time: 0, duration: 31,
                                       intensity: 0.5, sharpness: 0.5)
        XCTAssertThrowsError(try spec(events: [overlong], duration: 31).validated())
        let overflow = HapticEventSpec(kind: .continuous, time: 0.8, duration: 0.5,
                                       intensity: 0.5, sharpness: 0.5)
        XCTAssertThrowsError(try spec(events: [overflow]).validated())
    }

    func testParameterCurvesMustUseStrictlyIncreasingTimes() {
        let event = HapticEventSpec(kind: .continuous, time: 0, duration: 1, intensity: 1, sharpness: 0)
        let curve = HapticCurveSpec(parameter: .intensity, points: [
            .init(time: 0.5, value: 0.2), .init(time: 0.5, value: 0.8)
        ])
        XCTAssertThrowsError(try spec(events: [event], curves: [curve]).validated())
    }

    func testExperimentClampsCorruptStoredSettings() throws {
        let configuration = ExperimentConfiguration(kind: .pulses, intensity: .nan, sharpness: 2,
                                                      duration: .infinity, interval: -2)
        let pattern = PatternFactory.experiment(configuration)
        XCTAssertNoThrow(try pattern.validated())
        XCTAssertLessThanOrEqual(pattern.events.count, 63)
        XCTAssertEqual(pattern.events.first?.intensity, 0.65)
        XCTAssertEqual(pattern.events.first?.sharpness, 1)
    }

    func testPulseTimesMatchRequestedIntervalWithoutAnExtraFinalBeat() throws {
        let pattern = PatternFactory.experiment(ExperimentConfiguration(kind: .pulses, duration: 1, interval: 0.2))
        XCTAssertNoThrow(try pattern.validated())
        XCTAssertEqual(pattern.events.count, 5)
        for (index, event) in pattern.events.enumerated() {
            XCTAssertEqual(event.time, Double(index) * 0.2, accuracy: 0.000_001)
            XCTAssertLessThan(event.time, pattern.duration)
        }
    }

    func testMetronomePreservesFourBeatLoopIncludingTrailingSilence() throws {
        for bpm in [40.0, 100.0, 200.0] {
            let pattern = PatternFactory.metronome(bpm: bpm, intensity: 0.8, sharpness: 0.5)
            XCTAssertNoThrow(try pattern.validated())
            let taps = pattern.events.filter { $0.kind == .tap }
            XCTAssertEqual(taps.count, 4)
            XCTAssertEqual(pattern.duration, 4 * 60 / bpm, accuracy: 0.000_001)
            XCTAssertEqual(taps[0].intensity, 0.8)
            XCTAssertLessThan(taps[1].intensity, taps[0].intensity)
            XCTAssertEqual(pattern.events.last?.duration, pattern.duration)
            XCTAssertEqual(pattern.events.last?.intensity, 0)
        }
    }

    private func spec(events: [HapticEventSpec], duration: Double = 1,
                      curves: [HapticCurveSpec] = []) -> HapticPatternSpec {
        HapticPatternSpec(id: "test", name: "test", subtitle: "", symbol: "waveform",
                          category: "test", duration: duration, events: events, curves: curves)
    }
}
