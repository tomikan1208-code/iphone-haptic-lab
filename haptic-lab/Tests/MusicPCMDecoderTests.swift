import AVFoundation
import XCTest
@testable import HapticLab

final class MusicPCMDecoderTests: XCTestCase {
    func testStereoResamplingUsesValidFramesAt44100And48000WithoutDoublingTimeOrChangingPitch() throws {
        for rate in [44_100.0, 48_000.0] {
            for interleaved in [false, true] {
                let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                    sampleRate: rate, channels: 2, interleaved: interleaved))
                let decoder = try MusicPCMDecoder(format: format, duration: 2.5)
                let total = Int(rate * 2.5)
                var frame = 0
                while frame < total {
                    let count = min(997, total - frame)
                    let buffer = try Self.pcm(format: format, start: frame, count: count, capacity: 4_096)
                    try decoder.append(buffer, at: Double(frame) / rate)
                    frame += count
                }
                let track = try decoder.finish(hash: String(repeating: "a", count: 64))
                try assertTimingAndPitch(track, duration: 2.5)
            }
        }
    }

    func testNativeStereoAACAtBothYouTubeAndCameraRatesPreservesDurationPitchAndOnsets() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for rate in [44_100.0, 48_000.0] {
            let audio = folder.appendingPathComponent("\(Int(rate)).m4a")
            try Self.writeAAC(audio, rate: rate)
            let duration = try await AVURLAsset(url: audio).load(.duration).seconds
            XCTAssertEqual(duration, 3, accuracy: 0.06)
            let track = try await MusicAnalyzer.analyze(audio) { _, _ in }
            XCTAssertEqual(track.duration, duration, accuracy: 1 / 22_050)
            try assertTimingAndPitch(track, duration: duration)
            let legacyDuration = try await legacyReaderDuration(audio, duration: duration)
            print("PCM duration verification: sourceRate=\(rate), media=\(duration), previousReader=\(legacyDuration), corrected=\(track.duration)")
        }
    }

    func testConverterRetainsMediaLeadingAndTrailingSilenceAcrossSampleRateChange() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let decoder = try MusicPCMDecoder(format: format, duration: 2)
        try decoder.append(Self.pcm(format: format, start: 0, count: 44_100), at: 0.5)
        let track = try decoder.finish(hash: String(repeating: "a", count: 64))
        XCTAssertEqual(track.duration, 2, accuracy: 1 / 22_050)
        XCTAssertEqual(track.value(at: 0.3).energy, 0)
        XCTAssertGreaterThan(track.value(at: 1.03).bass, 0.5)
        XCTAssertEqual(track.value(at: 1.8).energy, 0)
    }

    func testDoubledSourceClockCannotProduceAnApparentlyValidSavedTrack() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let buffer = try Self.pcm(format: format, start: 0, count: 44_100)
        let decoder = try MusicPCMDecoder(format: format, duration: 1)
        XCTAssertThrowsError(try decoder.append(buffer, at: 1))
    }

    @MainActor
    func testLegacyDoubledYouTubeCacheRebuildsOncePreservingGainHistoryAndOldDataUntilSuccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = MusicLibraryDisk(root: root)
        try disk.initialize()
        let audio = root.appendingPathComponent("fixture.m4a")
        try Self.writeAAC(audio, rate: 44_100)
        var selection = try MusicSelection.youtube(id: "oqpx_KV6ohM")
        selection.duration = 6
        var old = MusicHapticTrack(version: 2, audioSHA256: String(repeating: "a", count: 64), duration: 6,
            envelope: [0.0, 6.0].map { .init(time: $0, bass: 0.4, energy: 0.4, sharpness: 0.2) }, taps: [])
        old.analysis = MusicAnalysisInfo(engine: "device", elapsedSeconds: 1, sampleRate: 22_050,
            hopMilliseconds: 20, fftSize: 1_024)
        let bytes = try JSONEncoder().encode(old)
        try bytes.write(to: disk.tracks.appendingPathComponent("legacy.json"))
        var record = MusicRecord(selection: selection)
        record.trackFilename = "legacy.json"
        record.trackBytes = bytes.count
        record.analysis = old.analysis
        record.settings.gain = 2.5
        record.lastPlayedAt = Date(timeIntervalSince1970: 1_000)
        try disk.write([record])
        var services = MusicPreparationServices()
        services.youtubeAudioURL = { selection in
            XCTAssertEqual(selection.videoID, "oqpx_KV6ohM")
            return URL(string: "https://test.googlevideo.com/audio")!
        }
        services.download = { _, destination, _ in
            try FileManager.default.copyItem(at: audio, to: destination)
            return destination
        }
        let library = MusicLibrary(root: root, services: services)
        XCTAssertTrue(try XCTUnwrap(library.record(for: selection)).requiresAudioReanalysis)
        library.prepare(selection)
        XCTAssertEqual(try library.disk.track(XCTUnwrap(library.record(for: selection))), old)
        for _ in 0..<1_000 {
            if library.preparation == nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(library.preparation)
        let repaired = try XCTUnwrap(library.record(for: selection), library.message ?? "No repaired track")
        let track = try library.disk.track(repaired)
        XCTAssertEqual(track.duration, 3, accuracy: 0.06)
        XCTAssertEqual(repaired.selection.duration ?? -1, track.duration)
        XCTAssertEqual(repaired.settings.gain, 2.5)
        XCTAssertEqual(repaired.lastPlayedAt, record.lastPlayedAt)
        XCTAssertEqual(repaired.analysis?.decoderVersion, MusicAnalyzer.decoderVersion)
        XCTAssertFalse(repaired.requiresAudioReanalysis)
        XCTAssertFalse(FileManager.default.fileExists(atPath: disk.tracks.appendingPathComponent("legacy.json").path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: disk.working.path).isEmpty)
        XCTAssertNil(repaired.mediaFilename)
        let restored = MusicLibrary(root: root)
        XCTAssertFalse(try XCTUnwrap(restored.record(for: selection)).requiresAudioReanalysis)
    }

    private func assertTimingAndPitch(_ track: MusicHapticTrack, duration: Double) throws {
        XCTAssertEqual(track.duration, duration, accuracy: 1 / 22_050)
        for onset in [0.5, 1.5] {
            XCTAssertTrue(track.taps.contains { abs($0.time - onset) < 0.08 }, "Missing onset at \(onset)")
        }
        XCTAssertEqual(track.value(at: 0.2).energy, 0)
        XCTAssertEqual(track.value(at: 2).energy, 0)
        XCTAssertGreaterThan(track.value(at: 0.53).bass, 0.5)
        let spectrum = try XCTUnwrap(track.spectrum(at: 0.53))
        let peak = try XCTUnwrap(spectrum.indices.max { spectrum[$0] < spectrum[$1] })
        XCTAssertLessThanOrEqual(abs(peak - (MusicFrequencyBands.index(for: 80) ?? -100)), 1)
    }

    private static func pcm(format: AVAudioFormat, start: Int, count: Int, capacity: Int? = nil) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capacity ?? count)))
        let channels = try XCTUnwrap(buffer.floatChannelData)
        // Unused allocation contains an audible poison value: only frameLength is valid audio.
        for channel in 0..<(format.isInterleaved ? 1 : Int(format.channelCount)) {
            channels[channel].initialize(repeating: 9, count: Int(buffer.frameCapacity) * buffer.stride)
        }
        buffer.frameLength = AVAudioFrameCount(count)
        for frame in 0..<count {
            let time = Double(start + frame) / format.sampleRate
            var value: Float = 0
            for onset in [0.5, 1.5] where time >= onset && time < onset + 0.1 {
                value = Float(sin(2 * .pi * 80 * (time - onset)) * exp(-(time - onset) * 20) * 0.7)
            }
            if format.isInterleaved {
                channels[0][frame * 2] = value
                channels[0][frame * 2 + 1] = -value
            } else {
                channels[0][frame] = value
                channels[1][frame] = -value
            }
        }
        return buffer
    }

    private static func writeAAC(_ url: URL, rate: Double) throws {
        let writer = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        var frame = 0
        let total = Int(rate * 3)
        while frame < total {
            let count = min(4_096, total - frame)
            try writer.write(from: pcm(format: writer.processingFormat, start: frame, count: count))
            frame += count
        }
    }

    // Measure the old reader's resampled clock without generating or saving haptics.
    private func legacyReaderDuration(_ url: URL, duration: Double) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let audio = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 22_050,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        XCTAssertTrue(reader.startReading())
        defer { reader.cancelReading() }
        var frames = 0
        while let sample = output.copyNextSampleBuffer() {
            let description = try XCTUnwrap(CMSampleBufferGetFormatDescription(sample))
            let format = try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(description))
            let data = try XCTUnwrap(CMSampleBufferGetDataBuffer(sample))
            let count = CMBlockBufferGetDataLength(data) / MemoryLayout<Float>.size / Int(format.pointee.mChannelsPerFrame)
            let start = Int((CMSampleBufferGetPresentationTimeStamp(sample).seconds * 22_050).rounded())
            frames = max(frames, start + count)
        }
        XCTAssertEqual(reader.status, .completed)
        return max(duration, Double(frames) / 22_050)
    }
}
