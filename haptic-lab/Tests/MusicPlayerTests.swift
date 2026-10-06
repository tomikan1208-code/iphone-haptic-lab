import XCTest
import CoreHaptics
@testable import HapticLab

final class MusicPlayerTests: XCTestCase {
    func testYouTubeDurationGateAcceptsRealAudioPaddingAndRejectsUnknownDuration() {
        var gate = MusicDurationGate()
        XCTAssertEqual(gate.check(duration: 547, expected: 546.97, playing: true, hostTime: 1), .matching)
        for span in [0, -1, Double.nan, Double.infinity] {
            XCTAssertEqual(gate.check(duration: span, expected: 546.97, playing: true, hostTime: 2), .waiting)
        }
    }

    func testYouTubeDurationGateWaitsForStablePlaybackAndRecoversWithoutLooseningTolerance() {
        var gate = MusicDurationGate()
        XCTAssertEqual(gate.check(duration: 30, expected: 547, playing: true, hostTime: 10), .waiting)
        XCTAssertEqual(gate.check(duration: 30, expected: 547, playing: true, hostTime: 10.5), .waiting)
        XCTAssertEqual(gate.check(duration: 60, expected: 547, playing: true, hostTime: 10.9), .waiting)
        XCTAssertEqual(gate.check(duration: 60, expected: 547, playing: true, hostTime: 11.95), .different)
        XCTAssertEqual(gate.check(duration: 547, expected: 547, playing: true, hostTime: 12), .matching)
        XCTAssertEqual(gate.check(duration: 30, expected: 547, playing: true, hostTime: 13), .waiting)
    }

    func testPausedMismatchingDurationCannotBecomeConfirmedThroughElapsedTime() {
        var gate = MusicDurationGate()
        XCTAssertEqual(gate.check(duration: 30, expected: 547, playing: false, hostTime: 0), .waiting)
        XCTAssertEqual(gate.check(duration: 30, expected: 547, playing: false, hostTime: 100), .waiting)
        XCTAssertEqual(gate.check(duration: 30, expected: 547, playing: true, hostTime: 101), .waiting)
        XCTAssertEqual(gate.check(duration: 30, expected: 547, playing: true, hostTime: 102), .different)
    }

    @MainActor
    func testIframeLoadingForeignVideoAndPausedSnapshotsDoNotReplaceSavedSongDuration() throws {
        let playback = MusicPlayback()
        let selection = try MusicSelection.youtube(id: "lkiV3U0GfGg")
        playback.load(selection, track: fixture(), mediaURL: nil, settings: MusicSettings())
        for (state, videoID, span) in [(-1, "lkiV3U0GfGg", 30.0), (3, "lkiV3U0GfGg", 30.0),
                                      (1, "dQw4w9WgXcQ", 30.0), (1, "lkiV3U0GfGg", 0.0),
                                      (2, "lkiV3U0GfGg", 30.0)] {
            playback.receiveYouTube(iframeSnapshot(state: state, videoID: videoID, duration: span), videoID: "lkiV3U0GfGg")
            XCTAssertEqual(playback.duration, 8)
            XCTAssertEqual(playback.position, 0)
            XCTAssertFalse(playback.isPlaying)
            XCTAssertNil(playback.message)
        }
        playback.receiveYouTube(iframeSnapshot(duration: 8, time: 2), videoID: "lkiV3U0GfGg")
        XCTAssertEqual(playback.position, 2)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertNil(playback.message)
        playback.stop()
    }

    @MainActor
    func testConfirmedIframeDurationDiagnosticClearsAutomaticallyWhenMainVideoReturns() async throws {
        let playback = MusicPlayback()
        playback.load(try MusicSelection.youtube(id: "lkiV3U0GfGg"), track: fixture(), mediaURL: nil, settings: MusicSettings())
        playback.receiveYouTube(iframeSnapshot(duration: 30), videoID: "lkiV3U0GfGg")
        XCTAssertNil(playback.message)
        XCTAssertEqual(playback.duration, 8)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        playback.receiveYouTube(iframeSnapshot(duration: 30, time: 1.1), videoID: "lkiV3U0GfGg")
        XCTAssertTrue(playback.message?.contains("動画 0:30・解析 0:08") == true)
        XCTAssertEqual(playback.position, 0)
        XCTAssertEqual(playback.duration, 8)
        playback.message = nil
        playback.receiveYouTube(iframeSnapshot(duration: 30, time: 1.2), videoID: "lkiV3U0GfGg")
        XCTAssertNil(playback.message, "A dismissed duration diagnostic must not reappear every frame")
        playback.receiveYouTube(iframeSnapshot(duration: 8, time: 0.1), videoID: "lkiV3U0GfGg")
        XCTAssertNil(playback.message)
        XCTAssertEqual(playback.position, 0.1)
        XCTAssertTrue(playback.isPlaying)
        playback.stop()
    }

    private func iframeSnapshot(state: Int = 1, videoID: String = "lkiV3U0GfGg", duration: Double, time: Double = 0) -> [String: Any] {
        ["state": state, "videoID": videoID, "duration": duration, "time": time, "rate": 1.0,
         "sent": Date().timeIntervalSince1970 * 1_000]
    }

    func testGainCanAmplifyQuietSavedTrackToFullOutputWithoutChangingAudioBands() throws {
        let track = MusicHapticTrack(version: 2, audioSHA256: String(repeating: "a", count: 64), duration: 2,
            envelope: [0.0, 2.0].map { .init(time: $0, bass: 0.72, energy: 0.5, sharpness: 0.4, mid: 0.4, high: 0.2) }, taps: [],
            spectrum: [0.0, 2.0].map { .init(time: $0, levels: Array(repeating: 0.4, count: 24)) })
        var settings = MusicSettings()
        let quiet = track.output(at: 0.2, settings: settings).level
        XCTAssertGreaterThan(quiet, 0.29)
        XCTAssertLessThan(quiet, 0.31)
        settings.gain = 2
        XCTAssertEqual(track.output(at: 0.2, settings: settings).level, quiet / 0.7 * 2, accuracy: 0.000001)
        settings.gain = 4
        let full = try XCTUnwrap(HapticVisualSignal.spectrum(track: track, time: 0.2, settings: settings, active: true))
        XCTAssertEqual(full.output.level, 1)
        XCTAssertEqual(full.haptics.max(), 1)
        XCTAssertEqual(full.audio, Array(repeating: 0.4, count: 24))
        let pattern = try XCTUnwrap(track.segment(at: 0.2, length: 0.3, settings: settings).first)
        XCTAssertEqual(pattern.curves.first?.points.first?.value, full.output.continuous)
        XCTAssertNoThrow(try pattern.validated())
        XCTAssertEqual(settings.intensity(for: .init(time: 0, bass: 0, energy: 0, sharpness: 0, mid: 0, high: 0)), 0)
        settings.gain = 0
        XCTAssertEqual(track.output(at: 0.2, settings: settings).level, 0)
    }

    @MainActor
    func testAmplifiedTapsClampBeforeDecaySoRendererAndBothDisplaysMatch() throws {
        var track = fixture()
        track.spectrum = [0.0, 8.0].map { .init(time: $0, levels: Array(repeating: 0.4, count: 24)) }
        let settings = MusicSettings(mode: .beats, gain: 4)
        let pattern = try XCTUnwrap(track.segment(at: 0.5, length: 0.1, settings: settings).first)
        XCTAssertEqual(pattern.events.first?.intensity, 1)
        XCTAssertNoThrow(try MusicHapticRenderer.makePattern(pattern))
        XCTAssertEqual(track.output(at: 0.5, settings: settings).transient, 1)
        XCTAssertEqual(track.output(at: 0.53, settings: settings).transient, 0.5, accuracy: 0.000001)
        XCTAssertEqual(HapticVisualSignal.spectrum(track: track, time: 0.53, settings: settings, active: true)?.haptics.max() ?? -1, 0.5, accuracy: 0.000001)
        XCTAssertEqual(HapticVisualSignal.level(track: track, time: 0.53, settings: settings), 0.5, accuracy: 0.000001)
    }

    func testOlderGainValuesDecodeUnchangedAndInvalidBoostCannotExceedHardwareBounds() throws {
        let legacy = try JSONDecoder().decode(MusicSettings.self, from: Data(#"{"mode":"mix","gain":0.25,"bass":0.65,"density":0.7,"offset":0}"#.utf8))
        XCTAssertEqual(legacy.normalized.gain, 0.25)
        XCTAssertEqual(MusicSettings(gain: 5).normalized.gain, 4)
        XCTAssertEqual(MusicSettings(gain: -1).normalized.gain, 0)
        XCTAssertEqual(MusicSettings(gain: .nan).normalized.gain, 0.7)
        XCTAssertEqual(MusicSettings(gain: .infinity).normalized.gain, 0.7)
        XCTAssertEqual(MusicSettings(gain: 4).amplified(.nan), 0)
    }

    func testBoostedContinuousDisplayInterpolatesClippedHardwareCurveAcrossArbitrarySegmentBoundaries() throws {
        let track = MusicHapticTrack(version: 1, audioSHA256: String(repeating: "a", count: 64), duration: 2,
            envelope: [.init(time: 0, bass: 0, energy: 0.1, sharpness: 0.3),
                       .init(time: 1, bass: 0, energy: 0.9, sharpness: 0.3),
                       .init(time: 2, bass: 0, energy: 0.9, sharpness: 0.3)], taps: [])
        let settings = MusicSettings(mode: .energy, gain: 4)
        let pattern = try XCTUnwrap(track.segment(at: 0.23, length: 0.57, settings: settings).first)
        let points = try XCTUnwrap(pattern.curves.first { $0.parameter == .intensity }?.points)
        XCTAssertEqual(points.count, 2)
        let fraction = (0.5 - 0.23) / 0.57
        let hardware = points[0].value + (points[1].value - points[0].value) * fraction
        XCTAssertEqual(hardware, 0.61, accuracy: 0.000001)
        XCTAssertEqual(track.output(at: 0.5, settings: settings).continuous, hardware, accuracy: 0.000001)
        XCTAssertEqual(HapticVisualSignal.level(track: track, time: 0.5, settings: settings), hardware, accuracy: 0.000001)
        XCTAssertNoThrow(try pattern.validated())
    }

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
