import XCTest
import CoreHaptics
@testable import HapticLab

final class MusicPlayerTests: XCTestCase {
    func testSavedSpectrumMeasuresAudioFrequencyInsteadOfStrengthModulation() throws {
        for frequency in [80.0, 300.0, 3_000.0] {
            let extractor = try MusicSignalExtractor(channels: 1)
            try extractor.append((0..<22_050).map { Float(0.4 * sin(Double($0) * 2 * .pi * frequency / 22_050)) })
            let track = try extractor.finish(hash: String(repeating: "a", count: 64))
            let spectrum = try XCTUnwrap(track.spectrum(at: 0.5))
            let peak = try XCTUnwrap(spectrum.indices.max { spectrum[$0] < spectrum[$1] })
            XCTAssertLessThanOrEqual(abs(peak - (MusicFrequencyBands.index(for: frequency) ?? -100)), 1)
            XCTAssertGreaterThan(spectrum[peak], 0.9)
            XCTAssertEqual(track.version, 2)
            XCTAssertNoThrow(try JSONDecoder().decode(MusicHapticTrack.self, from: JSONEncoder().encode(track)).validated())
        }
    }

    func testVisualizationUsesGainModeAndSyncOffsetOfActualTrack() {
        let track = fixture()
        var settings = MusicSettings()
        settings.gain = 0
        XCTAssertEqual(HapticVisualSignal.level(track: track, time: 1, settings: settings), 0)
        settings.gain = 1
        settings.mode = .beats
        XCTAssertEqual(HapticVisualSignal.level(track: track, time: 0.5, settings: settings), 0.7, accuracy: 0.000001)
        settings.offset = 0.2
        XCTAssertEqual(HapticVisualSignal.level(track: track, time: 0.5, settings: settings), 0)
        XCTAssertEqual(HapticVisualSignal.level(track: track, time: 0.7, settings: settings), 0.7, accuracy: 0.000001)
        XCTAssertEqual(HapticVisualSignal.level(track: track, time: -1, settings: settings), 0)
    }

    func testMusicalCompositionFindsTempoAndCreatesBoundedAccents() throws {
        let track = fixture()
        XCTAssertEqual(MusicComposer.tempo(track.taps), 120, accuracy: 3)
        let composed = try MusicComposer.compose(track)
        XCTAssertNoThrow(try composed.validated())
        XCTAssertLessThan(composed.envelope[1].bass, track.envelope[1].bass)
        XCTAssertGreaterThan(composed.taps[0].intensity, composed.taps[1].intensity)
        for index in 1..<composed.taps.count {
            XCTAssertGreaterThanOrEqual(composed.taps[index].time - composed.taps[index - 1].time, 0.1)
        }
    }

    func testWaveformShowsLocalFourSecondsAndDoesNotAnticipateTaps() {
        let track = MusicHapticTrack(version: 1, audioSHA256: String(repeating: "c", count: 64), duration: 600,
            envelope: [.init(time: 0, bass: 0, energy: 0, sharpness: 0), .init(time: 600, bass: 0, energy: 0, sharpness: 0)],
            taps: [.init(time: 12.345, intensity: 0.8, sharpness: 0.3)])
        var settings = MusicSettings()
        settings.mode = .beats
        settings.gain = 1
        let bins = HapticVisualSignal.timeline(track: track, settings: settings, position: 12.345, count: 201)
        XCTAssertEqual(bins[100], 0.8, accuracy: 0.000001)
        XCTAssertEqual(bins[99], 0)
        XCTAssertGreaterThan(bins[101], 0)
        XCTAssertEqual(HapticVisualSignal.level(track: track, time: 12.344, settings: settings), 0)
        settings.gain = 0
        XCTAssertEqual(HapticVisualSignal.timeline(track: track, settings: settings, position: 12.345, count: 201).max(), 0)
    }

    func testGreenSpectrumAndRendererUseTheSameIntensityOffsetAndDensity() throws {
        var track = fixture()
        let levels = (0..<24).map { 0.2 + Double($0) * 0.02 }
        track.spectrum = [.init(time: 0, levels: levels), .init(time: 8, levels: levels)]
        var settings = MusicSettings()
        settings.gain = 0.8
        settings.offset = 0.2
        let snapshot = try XCTUnwrap(HapticVisualSignal.spectrum(track: track, time: 0.7, settings: settings, active: true))
        XCTAssertEqual(snapshot.haptics.max() ?? -1, 0.7 * settings.gain, accuracy: 0.000001)
        let pattern = try XCTUnwrap(track.segment(at: 0.5, length: 0.1, settings: settings).first { $0.id == "music-taps" })
        XCTAssertEqual(pattern.events[0].intensity, snapshot.output.transient, accuracy: 0.000001)
        XCTAssertEqual(HapticVisualSignal.spectrum(track: track, time: 0.7, settings: settings, active: false)?.haptics.max(), 0)
        settings.mode = .bass
        let bass = try XCTUnwrap(HapticVisualSignal.spectrum(track: track, time: 0.7, settings: settings, active: true))
        let bed = try XCTUnwrap(track.segment(at: 0.5, length: 0.1, settings: settings).first { $0.id == "music-bed" })
        XCTAssertEqual(bass.haptics.max() ?? -1, bed.curves[0].points[0].value, accuracy: 0.000001)
        XCTAssertEqual(bass.haptics[23], 0)
        settings.gain = 0
        XCTAssertEqual(HapticVisualSignal.spectrum(track: track, time: 0.7, settings: settings, active: true)?.haptics.max(), 0)
    }

    func testDisplayClockInterpolatesPlaybackRateAndFreezesOnPauseStallAndSeek() {
        var clock = MusicMediaClock()
        clock.update(position: 1, playing: true, rate: 2, hostTime: 10)
        XCTAssertEqual(clock.position(at: 10.02), 1.04, accuracy: 0.000001)
        clock.update(position: 1, playing: true, rate: 2, hostTime: 10.04)
        XCTAssertEqual(clock.position(at: 10.06), 1.12, accuracy: 0.000001)
        XCTAssertEqual(clock.position(at: 11), 1.5, accuracy: 0.000001)
        clock.update(position: 1, playing: true, rate: 2, hostTime: 10.4)
        XCTAssertEqual(clock.position(at: 10.5), 1)
        clock.update(position: 1.2, playing: false, rate: 2, hostTime: 10.6)
        XCTAssertEqual(clock.position(at: 12), 1.2)
        clock.reset(to: 5)
        XCTAssertEqual(clock.position(at: 12), 5)
    }

    func testLegacyTrackHasNoInventedSpectrumAndCorruptBandsAreRejected() throws {
        var track = fixture()
        XCTAssertNil(HapticVisualSignal.spectrum(track: track, time: 1, settings: .init(), active: true))
        track.spectrum = [.init(time: 0, levels: [.nan])]
        XCTAssertThrowsError(try track.validated())
        track.spectrum = [.init(time: 0, levels: Array(repeating: 0.4, count: 24)),
                          .init(time: 0, levels: Array(repeating: 0.4, count: 24))]
        XCTAssertThrowsError(try track.validated())
    }

    func testOrchestralArrangementRetainsDynamicsAndNaturalAccentsWithSilentRest() throws {
        let track = MusicHapticTrack(version: 1, audioSHA256: String(repeating: "b", count: 64), duration: 4,
            envelope: (0...200).map { index in
                let energy = index < 150 ? Double(index) / 150 : 0
                return .init(time: Double(index) * 0.02, bass: energy, energy: energy, sharpness: 0.8)
            }, taps: [.init(time: 0.31, intensity: 0.9, sharpness: 0.8), .init(time: 0.54, intensity: 0.8, sharpness: 0.9),
                      .init(time: 1.37, intensity: 0.85, sharpness: 0.7), .init(time: 1.6, intensity: 0.2, sharpness: 0.4)])
        let arranged = try MusicComposer.orchestral(track)
        XCTAssertNoThrow(try arranged.validated())
        XCTAssertEqual(arranged.taps.map(\.time), [0.31, 1.37])
        XCTAssertGreaterThan(arranged.value(at: 2.8).energy, arranged.value(at: 1).energy * 2)
        XCTAssertEqual(arranged.value(at: 3.5).energy, 0)
        XCTAssertTrue(arranged.taps.allSatisfy { $0.intensity <= 0.4 && $0.sharpness <= 0.35 })
    }

    func testOlderSavedTracksAndRecordsStillDecodeWithoutAnalysisMetadata() throws {
        let track = fixture()
        let data = try JSONEncoder().encode(track)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "analysis")
        let older = try JSONDecoder().decode(MusicHapticTrack.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(older.analysis)
        XCTAssertNoThrow(try older.validated())
        let recordJSON = try JSONEncoder().encode(MusicRecord(selection: .file(URL(fileURLWithPath: "/sample.wav"))))
        XCTAssertNil(try JSONDecoder().decode(MusicRecord.self, from: recordJSON).analysis)
    }

    func testPCConnectionAcceptsPrivateAddressesAndRejectsPlaintextPublicHosts() throws {
        let token = String(repeating: "a", count: 32)
        for address in ["http://192.168.1.10:8765", "http://10.1.2.3:8765", "http://127.0.0.1:8765", "http://desktop.local:8765"] {
            XCTAssertNoThrow(try PCServerConnection(address: address, token: token))
        }
        for address in ["http://example.com", "http://172.32.1.1", "https://user:password@example.com", "file:///tmp/server", "http://10.1.1.999", "http://10.invalid.1.2.3", "http://.10.1.2.3"] {
            XCTAssertThrowsError(try PCServerConnection(address: address, token: token))
        }
    }

    @MainActor
    func testPCTrackWithTenMillisecondEnvelopeDecodesAndBuildsHapticPatterns() throws {
        var track = MusicHapticTrack(version: 1, audioSHA256: String(repeating: "d", count: 64), duration: 2,
            envelope: (0...200).map { .init(time: Double($0) * 0.01, bass: 0.7, energy: 0.5, sharpness: 0.4) },
            taps: [.init(time: 0.37, intensity: 0.8, sharpness: 0.5)])
        track.analysis = .init(engine: "pc", elapsedSeconds: 1.2, sampleRate: 44100, hopMilliseconds: 10,
                               fftSize: 4096, serverTrackID: String(repeating: "e", count: 64), style: .following, profile: .orchestral)
        let decoded = try JSONDecoder().decode(MusicHapticTrack.self, from: JSONEncoder().encode(track)).validated()
        XCTAssertEqual(decoded.analysis, track.analysis)
        for specification in decoded.segment(at: 0.1, length: 0.8) {
            XCTAssertNoThrow(try MusicHapticRenderer.makePattern(specification))
        }
    }

    func testAudioDownloadURLCanHaveNoExtensionButCannotBeVideoPageOrCredentials() throws {
        XCTAssertNoThrow(try MusicSelection.audioDownloadURL("https://example.com/download?id=track"))
        for address in ["https://youtube.com/watch?v=dQw4w9WgXcQ", "https://example.com/page.html", "http://example.com/song.mp3", "https://user:secret@example.com/song.mp3"] {
            XCTAssertThrowsError(try MusicSelection.audioDownloadURL(address))
        }
    }

    private func fixture() -> MusicHapticTrack {
        MusicHapticTrack(version: 1, audioSHA256: String(repeating: "a", count: 64), duration: 8,
            envelope: (0...400).map { .init(time: Double($0) * 0.02, bass: 0.7, energy: 0.7, sharpness: 0.4) },
            taps: (1..<16).map { .init(time: Double($0) * 0.5, intensity: 0.7, sharpness: 0.5) })
    }
}
