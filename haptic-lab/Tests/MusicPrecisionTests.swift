import AVFoundation
import CoreHaptics
import XCTest
@testable import HapticLab

final class MusicPrecisionTests: XCTestCase {
    func testThreeBassBandsKeepTheirBalanceAndOppositePhaseStereoAtTenMilliseconds() throws {
        for (frequency, dominant) in [(50.0, 0), (100.0, 1), (220.0, 2)] {
            let mono = try extract(channels: 1, duration: 1) { sin(2 * .pi * frequency * $0) * 0.5 }
            let stereo = try extract(channels: 2, duration: 1) { sin(2 * .pi * frequency * $0) * 0.5 }
            XCTAssertEqual(stereo.duration, 1, accuracy: 0.000_1)
            XCTAssertEqual(stereo.envelope[1].time - stereo.envelope[0].time, 0.01, accuracy: 0.000_001)
            let point = stereo.value(at: 0.5)
            let texture = try XCTUnwrap(point.texture)
            let values = [texture.sub, texture.kick, texture.body]
            XCTAssertGreaterThan(values[dominant], 0.85)
            XCTAssertLessThan(values.enumerated().filter { $0.offset != dominant }.map(\.element).max() ?? 0, 0.20)
            XCTAssertEqual(mono.value(at: 0.5).bass, point.bass, accuracy: 0.000_1)
            let levels = try XCTUnwrap(stereo.spectrum(at: 0.5))
            let peak = try XCTUnwrap(levels.indices.max(by: { levels[$0] < levels[$1] }))
            XCTAssertLessThanOrEqual(abs(peak - (MusicFrequencyBands.index(for: frequency) ?? -100)), 1)
        }
    }

    @MainActor
    func testKickMidAndHighAttacksHaveDifferentTouchWithoutEarlyOrSilentTaps() throws {
        let events = [(0.5, 80.0), (1.3, 900.0), (2.1, 5_000.0)]
        let track = try extract(channels: 2, duration: 2.8) { time in
            for (onset, frequency) in events where time >= onset && time < onset + 0.12 {
                return sin(2 * .pi * frequency * (time - onset)) * exp(-(time - onset) * 24) * 0.7
            }
            return 0
        }
        var detected: [MusicTap] = []
        for (onset, _) in events {
            let tap = try XCTUnwrap(track.taps.filter { abs($0.time - onset) <= 0.04 }.max(by: { $0.intensity < $1.intensity }))
            detected.append(tap)
        }
        XCTAssertLessThan(detected[0].sharpness, detected[1].sharpness)
        XCTAssertLessThan(detected[1].sharpness, detected[2].sharpness)
        XCTAssertGreaterThan(detected[0].intensity, detected[1].intensity)
        XCTAssertGreaterThan(detected[1].intensity, detected[2].intensity)
        let settings = MusicSettings(mode: .beats, gain: 3, bass: 1, density: 1)
        let high = try XCTUnwrap(HapticVisualSignal.spectrum(track: track, time: detected[2].time, settings: settings, active: true))
        XCTAssertEqual(high.haptics.max() ?? -1, high.output.level, accuracy: 0.000_001)
        XCTAssertTrue(high.haptics.enumerated().filter { MusicFrequencyBands.centers[$0.offset] < 2_000 }.allSatisfy { $0.element == 0 })
        XCTAssertTrue(track.taps.allSatisfy { tap in events.contains { abs(tap.time - $0.0) <= 0.05 } })
        for time in [0.2, 0.9, 1.8, 2.6] {
            XCTAssertEqual(track.value(at: time).energy, 0)
            XCTAssertEqual(track.output(at: time, settings: MusicSettings()).level, 0)
            XCTAssertTrue(try XCTUnwrap(track.spectrum(at: time)).allSatisfy { $0 == 0 })
        }
        for start in [0.0, 1.0, 2.0] {
            for specification in track.segment(at: start, length: 1) { _ = try MusicHapticRenderer.makePattern(specification) }
        }
    }

    func testSustainedBassDoesNotBecomeRepeatedKickAndHighToneDoesNotBecomeHeavyContinuous() throws {
        let bass = try extract(channels: 1, duration: 2) { time in
            let fade = min(1, time / 0.2, (2 - time) / 0.2)
            return sin(2 * .pi * 80 * time) * fade * 0.5
        }
        XCTAssertFalse(bass.taps.contains { (0.4...1.7).contains($0.time) })
        let high = try extract(channels: 1, duration: 2) { sin(2 * .pi * 5_000 * $0) * 0.5 }
        let settings = MusicSettings(mode: .mix, gain: 1, bass: 1, density: 1)
        XCTAssertGreaterThan(bass.output(at: 1, settings: settings).continuous,
                             high.output(at: 1, settings: settings).continuous * 3)
    }

    func testSavedPrecisionBandsSurviveInterpolationCompositionAndLegacyDecoding() throws {
        let track = try extract(channels: 1, duration: 1) { sin(2 * .pi * 50 * $0) * 0.5 }
        let decoded = try JSONDecoder().decode(MusicHapticTrack.self, from: JSONEncoder().encode(track)).validated()
        XCTAssertEqual(decoded, track)
        XCTAssertNotNil(decoded.value(at: 0.505).texture)
        XCTAssertNotNil(try MusicComposer.orchestral(decoded).value(at: 0.5).texture)
        XCTAssertNotNil(try MusicComposer.compose(decoded).value(at: 0.5).texture)
        let legacy = try JSONDecoder().decode(MusicEnvelopePoint.self, from: Data(#"{"time":0,"bass":0.5,"energy":0.7,"sharpness":0.2}"#.utf8))
        XCTAssertNil(legacy.texture)
    }

    @MainActor
    func testNativePrecisionPipelineStoresMeasuredTimeQualityAndReloadsWithoutAnalysis() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "MusicDemo", withExtension: "wav"))
        let library = MusicLibrary(root: root)
        library.prepare(MusicSelection.file(url), audioFile: url, method: .device, style: .following, quality: .precision)
        let deadline = Date().addingTimeInterval(40)
        while library.preparation != nil, Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        let record = try XCTUnwrap(library.prepared.first, library.message ?? "No precision track")
        let info = try XCTUnwrap(record.analysis)
        XCTAssertEqual(info.quality, .precision)
        XCTAssertEqual(info.sampleRate, 44_100)
        XCTAssertEqual(info.fftSize, 4_096)
        XCTAssertEqual(info.hopMilliseconds, 10)
        XCTAssertGreaterThan(try XCTUnwrap(info.processingSeconds), 0)
        XCTAssertLessThanOrEqual(try XCTUnwrap(info.processingSeconds), info.elapsedSeconds)
        let track = try library.disk.track(record)
        XCTAssertEqual(track.duration, 12, accuracy: 0.02)
        XCTAssertNotNil(track.value(at: 1).texture)
        XCTAssertEqual(try MusicLibrary(root: root).disk.track(record), track)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: library.disk.working.path).isEmpty)
        print("DEVICE_PRECISION_BENCHMARK audioSeconds=12 analysisSeconds=\(info.processingSeconds ?? -1) preparationSeconds=\(info.elapsedSeconds)")
    }

    private func extract(channels: Int, duration: Double, signal: (Double) -> Double) throws -> MusicHapticTrack {
        let extractor = try MusicSignalExtractor(channels: channels, quality: .precision)
        let count = Int(duration * 44_100)
        // Exercise streaming overlap across a non-hop-aligned read size.
        for start in stride(from: 0, to: count, by: 3_997) {
            var samples: [Float] = []
            for index in start..<min(count, start + 3_997) {
                let value = Float(signal(Double(index) / 44_100))
                samples.append(value)
                if channels == 2 { samples.append(-value) }
            }
            try extractor.append(samples)
        }
        return try extractor.finish(hash: String(repeating: "a", count: 64))
    }
}
