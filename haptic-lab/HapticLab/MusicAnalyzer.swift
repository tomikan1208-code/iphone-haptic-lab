import Accelerate
import AVFoundation
import CryptoKit
import Foundation

struct MusicAudioFeature {
    let time: Double
    let rms: Double
    let bass: Double
    let flux: Double
    let brightness: Double
    let mid: Double
    let high: Double
    let bands: [Double]
    var detail: MusicPrecisionFeature? = nil
}

// Bounded PCM buffer; channel energies are measured independently, including opposite-phase stereo.
final class MusicSignalExtractor {
    static let sampleRate = 22_050.0
    static let windowSize = 1_024
    static let hopSize = 441
    private let quality: MusicAnalysisQuality
    private var fftSize: Int { quality.fftSize }
    private var rate: Double { quality.sampleRate }
    private let precision: MusicPrecisionProcessor?
    private let channels: Int
    private let setup: OpaquePointer
    private var window = [Float](repeating: 0, count: windowSize)
    private var pending: [Float] = []
    private var consumedFrames = 0
    private var totalFrames = 0
    private var previous: [[Float]]
    private var features: [MusicAudioFeature] = []

    init(channels: Int, quality: MusicAnalysisQuality = .standard) throws {
        guard (1...8).contains(channels),
              let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(Self.windowSize), .FORWARD) else {
            throw MusicError.unsupportedMedia
        }
        self.channels = channels
        self.quality = quality
        precision = quality == .precision ? try MusicPrecisionProcessor(channels: channels) : nil
        self.setup = setup
        previous = Array(repeating: Array(repeating: 0, count: Self.windowSize / 2), count: channels)
        vDSP_hann_window(&window, vDSP_Length(Self.windowSize), Int32(vDSP_HANN_NORM))
        // Center the first FFT on media time zero, matching the PC analyzer.
        pending = Array(repeating: 0, count: fftSize / 2 * channels)
        consumedFrames = -fftSize / 2
    }

    deinit { vDSP_DFT_DestroySetup(setup) }

    func append(_ interleavedSamples: [Float]) throws {
        guard interleavedSamples.count % channels == 0,
              interleavedSamples.allSatisfy({ $0.isFinite && abs($0) <= 16 }) else { throw MusicError.unsupportedMedia }
        totalFrames += interleavedSamples.count / channels
        guard Double(totalFrames) / rate <= MusicHapticTrack.maximumDuration + 0.1 else {
            throw MusicError.tooLong
        }
        pending.append(contentsOf: interleavedSamples)
        var readOffset = 0
        while pending.count - readOffset >= fftSize * channels {
            try Task.checkCancellation()
            features.append(measure(offset: readOffset))
            readOffset += Self.hopSize * channels
            consumedFrames += Self.hopSize
        }
        if readOffset > 0 { pending.removeFirst(readOffset) }
    }

    func append(_ samples: [Float], at presentationTime: Double) throws {
        guard presentationTime.isFinite, abs(presentationTime) <= MusicHapticTrack.maximumDuration + 1 else {
            throw MusicError.unsupportedMedia
        }
        let framePosition = Int((presentationTime * rate).rounded())
        let gap = framePosition - totalFrames
        if gap > 0 { try appendSilence(frames: gap) }
        let skipped = max(0, -gap) * channels
        if skipped < samples.count { try append(Array(samples.dropFirst(skipped))) }
    }

    private func appendSilence(frames: Int) throws {
        guard frames <= Int(MusicHapticTrack.maximumDuration * rate) else { throw MusicError.tooLong }
        var remaining = frames
        while remaining > 0 {
            let count = min(4_096, remaining)
            try append(Array(repeating: 0, count: count * channels))
            remaining -= count
        }
    }

    func finish(hash: String, expectedDuration: Double? = nil) throws -> MusicHapticTrack {
        if let expectedDuration {
            guard expectedDuration.isFinite, expectedDuration > 0, expectedDuration <= MusicHapticTrack.maximumDuration else {
                throw MusicError.tooLong
            }
            let missing = Int((expectedDuration * rate).rounded()) - totalFrames
            if missing > 0 { try appendSilence(frames: missing) }
        }
        let duration = Double(totalFrames) / rate
        guard duration > 0 else { throw MusicError.unsupportedMedia }
        pending.append(contentsOf: repeatElement(0, count: fftSize * channels))
        while Double(consumedFrames + fftSize / 2) / rate < duration {
            try Task.checkCancellation()
            features.append(measure(offset: 0))
            pending.removeFirst(Self.hopSize * channels)
            consumedFrames += Self.hopSize
        }
        if quality == .precision { return try MusicPrecisionProcessor.makeTrack(features: features, duration: duration, hash: hash) }
        return try Self.makeTrack(features: features, duration: duration, hash: hash)
    }

    private func measure(offset: Int) -> MusicAudioFeature {
        if let precision {
            return precision.measure(pending, offset: offset, time: Double(consumedFrames + fftSize / 2) / rate)
        }
        let n = Self.windowSize
        var rms = 0.0, bass = 0.0, mid = 0.0, high = 0.0, flux = 0.0, centroid = 0.0
        var bands = Array(repeating: 0.0, count: MusicFrequencyBands.count)
        let imaginary = [Float](repeating: 0, count: n)
        for channel in 0..<channels {
            var real = [Float](repeating: 0, count: n)
            var outReal = real, outImaginary = real
            var energy = 0.0
            for index in 0..<n {
                let sample = pending[offset + index * channels + channel]
                energy += Double(sample * sample)
                real[index] = sample * window[index]
            }
            vDSP_DFT_Execute(setup, real, imaginary, &outReal, &outImaginary)
            var bassEnergy = 0.0, midEnergy = 0.0, highEnergy = 0.0
            var magnitudeSum = 0.0, weightedSum = 0.0, increase = 0.0
            var bandEnergy = Array(repeating: 0.0, count: MusicFrequencyBands.count)
            for bin in 1..<(n / 2) {
                let magnitude = sqrt(outReal[bin] * outReal[bin] + outImaginary[bin] * outImaginary[bin])
                let frequency = Double(bin) * Self.sampleRate / Double(n)
                let power = Double(magnitude * magnitude)
                if (20..<120).contains(frequency) { bassEnergy += power }
                if (120..<500).contains(frequency) { midEnergy += power }
                if (500...8_000).contains(frequency) { highEnergy += power }
                if let band = MusicFrequencyBands.index(for: frequency) { bandEnergy[band] += power }
                if frequency <= 8_000 {
                    magnitudeSum += Double(magnitude)
                    weightedSum += Double(magnitude) * frequency
                    increase += Double(max(0, magnitude - previous[channel][bin]))
                }
                previous[channel][bin] = magnitude
            }
            rms += sqrt(energy / Double(n))
            bass += sqrt(bassEnergy) / Double(n)
            mid += sqrt(midEnergy) / Double(n)
            high += sqrt(highEnergy) / Double(n)
            for band in bands.indices { bands[band] += sqrt(bandEnergy[band]) / Double(n) }
            flux += increase / Double(n)
            centroid += magnitudeSum > 0 ? weightedSum / magnitudeSum / 6_000 : 0
        }
        let divisor = Double(channels)
        return MusicAudioFeature(time: Double(consumedFrames + n / 2) / Self.sampleRate,
                                 rms: rms / divisor, bass: bass / divisor,
                                 flux: flux / divisor, brightness: min(1, centroid / divisor),
                                 mid: mid / divisor, high: high / divisor, bands: bands.map { $0 / divisor })
    }

    static func makeTrack(features: [MusicAudioFeature], duration: Double, hash: String) throws -> MusicHapticTrack {
        let frames = features.filter { $0.time < duration }
        guard !frames.isEmpty, frames.contains(where: { $0.rms > 0.000_03 }) else { throw MusicError.emptyAudio }
        func reference(_ values: [Double]) -> Double {
            let sorted = values.filter { $0 > 0.000_01 }.sorted()
            return sorted.isEmpty ? 1 : max(0.000_01, sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))])
        }
        let rmsScale = reference(frames.map(\.rms)), bassScale = reference(frames.map(\.bass))
        let fluxScale = reference(frames.map(\.flux))
        let midScale = reference(frames.map(\.mid)), highScale = reference(frames.map(\.high))
        // One reference for every band in the song, preserving the relative spectral shape.
        let spectrumScale = max(reference(frames.map { $0.bands.max() ?? 0 }), rmsScale * 0.35)
        var envelope: [MusicEnvelopePoint] = []
        var taps: [MusicTap] = []
        var spectrum: [MusicSpectrumFrame] = []
        var smoothBass = 0.0, smoothEnergy = 0.0, smoothMid = 0.0, smoothHigh = 0.0
        for (index, frame) in frames.enumerated() {
            let audible = frame.rms > 0.000_03
            let bass = audible ? min(1, pow(frame.bass / bassScale, 0.7)) : 0
            let energy = audible ? min(1, pow(frame.rms / rmsScale, 0.7)) : 0
            let mid = audible ? min(1, pow(frame.mid / midScale, 0.7)) : 0
            let high = audible ? min(1, pow(frame.high / highScale, 0.7)) : 0
            // Short release keeps the display and touch close to each 20 ms source frame.
            smoothBass += (bass - smoothBass) * (bass > smoothBass ? 0.85 : 0.5)
            smoothEnergy += (energy - smoothEnergy) * (energy > smoothEnergy ? 0.85 : 0.5)
            smoothMid += (mid - smoothMid) * (mid > smoothMid ? 0.85 : 0.5)
            smoothHigh += (high - smoothHigh) * (high > smoothHigh ? 0.85 : 0.5)
            // Silence is absolute; smoothing must never create vibration in silent sections.
            if !audible { smoothBass = 0; smoothEnergy = 0; smoothMid = 0; smoothHigh = 0 }
            let sharpness = audible ? min(1, 0.12 + frame.brightness * 0.55 + smoothHigh * 0.3) : 0
            envelope.append(.init(time: frame.time, bass: smoothBass, energy: smoothEnergy, sharpness: sharpness,
                                  mid: smoothMid, high: smoothHigh))
            spectrum.append(.init(time: frame.time, levels: frame.bands.map {
                audible ? (min(1, pow($0 / spectrumScale, 0.7)) * 1_000).rounded() / 1_000 : 0
            }))
            let local = frames[max(0, index - 25)..<index].map(\.flux)
            let mean = local.isEmpty ? 0 : local.reduce(0, +) / Double(local.count)
            let variance = local.isEmpty ? 0 : local.reduce(0) { $0 + pow($1 - mean, 2) } / Double(local.count)
            let threshold = max(fluxScale * 0.16, mean + sqrt(variance) * 0.75)
            let before = index > 0 ? frames[index - 1].flux : 0
            let after = index + 1 < frames.count ? frames[index + 1].flux : 0
            if audible, frame.flux > threshold, frame.flux > before, frame.flux >= after,
               frame.time - (taps.last?.time ?? -1) >= 0.1 {
                let intensity = min(1, 0.2 + frame.flux / fluxScale * 0.8) * sqrt(energy)
                taps.append(.init(time: frame.time, intensity: intensity, sharpness: min(1, sharpness + 0.2)))
            }
        }
        let first = envelope[0], last = envelope[envelope.count - 1]
        if first.time > 0 {
            envelope.insert(.init(time: 0, bass: first.bass, energy: first.energy, sharpness: first.sharpness,
                                  mid: first.mid, high: first.high), at: 0)
            spectrum.insert(.init(time: 0, levels: spectrum[0].levels), at: 0)
        }
        envelope.append(.init(time: duration, bass: last.bass, energy: last.energy, sharpness: last.sharpness,
                              mid: last.mid, high: last.high))
        spectrum.append(.init(time: duration, levels: spectrum[spectrum.count - 1].levels))
        var track = MusicHapticTrack(version: MusicHapticTrack.currentVersion, audioSHA256: hash,
                                   duration: duration, envelope: envelope, taps: taps)
        track.spectrum = spectrum
        return try track.validated()
    }
}

enum MusicAnalyzer {
    static let maximumBytes: Int64 = 512 * 1_024 * 1_024
    static let decoderVersion = 2

    static func analyze(_ url: URL, quality: MusicAnalysisQuality = .standard,
                        progress: @escaping @Sendable (Double, String) -> Void) async throws -> MusicHapticTrack {
        // Audio-only files have their own decoded frame clock. Do not extend them
        // to an inaccurate movie/track duration reported by AVAsset.
        if ["wav", "m4a", "mp3", "aac", "aif", "aiff", "caf"].contains(url.pathExtension.lowercased()),
           let audio = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) {
            return try analyzeAudioFile(audio, url: url, quality: quality, progress: progress)
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw MusicError.unsupportedMedia }
        guard duration <= MusicHapticTrack.maximumDuration else { throw MusicError.tooLong }
        let protected = try await asset.load(.hasProtectedContent)
        guard !protected, let audio = try await asset.loadTracks(withMediaType: .audio).first else {
            throw MusicError.unsupportedMedia
        }
        progress(0.08, "音源を確認しています")
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audio, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: true
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw MusicError.unsupportedMedia }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? MusicError.unsupportedMedia }
        defer { reader.cancelReading() }
        var decoder: MusicPCMDecoder?
        var lastProgress = 0.0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let description = CMSampleBufferGetFormatDescription(sample) else { throw MusicError.unsupportedMedia }
            let format = AVAudioFormat(cmAudioFormatDescription: description)
            let count = CMSampleBufferGetNumSamples(sample)
            guard format.commonFormat == .pcmFormatFloat32, count >= 0,
                  count <= 8 * 1_024 * 1_024 / max(1, Int(format.channelCount) * MemoryLayout<Float>.size) else {
                throw MusicError.unsupportedMedia
            }
            if count == 0 { continue }
            guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else {
                throw MusicError.unsupportedMedia
            }
            pcm.frameLength = AVAudioFrameCount(count)
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(count), into: pcm.mutableAudioBufferList)
            guard status == noErr else { throw MusicError.unsupportedMedia }
            if decoder == nil { decoder = try MusicPCMDecoder(format: format, duration: duration, quality: quality) }
            let position = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            try decoder?.append(pcm, at: position)
            if position - lastProgress > 0.25 {
                progress(0.1 + min(1, position / duration) * 0.78, "低音とビートを解析中 · \(musicTime(position)) / \(musicTime(duration))")
                lastProgress = position
            }
        }
        guard reader.status == .completed, let decoder else { throw reader.error ?? MusicError.unsupportedMedia }
        progress(0.9, "振動のトラックを作成しています")
        return try decoder.finish(hash: audioHash(url))
    }

    private static func analyzeAudioFile(_ audio: AVAudioFile, url: URL, quality: MusicAnalysisQuality,
                                        progress: @escaping @Sendable (Double, String) -> Void) throws -> MusicHapticTrack {
        let format = audio.processingFormat
        let estimated = Double(audio.length) / format.sampleRate
        guard estimated.isFinite, estimated > 0 else { throw MusicError.unsupportedMedia }
        // Bound decoding by the app limit, not by a possibly inaccurate estimate.
        let decoder = try MusicPCMDecoder(format: format, duration: MusicHapticTrack.maximumDuration, quality: quality)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096) else {
            throw MusicError.unsupportedMedia
        }
        var frames = 0
        var lastProgress = -1.0
        while audio.framePosition < audio.length {
            try Task.checkCancellation()
            // AVAudioFile can throw a nil NSError for an extra read at EOF.
            // Limit each read to the remaining file frames, including the final partial buffer.
            let remaining = audio.length - audio.framePosition
            try audio.read(into: pcm, frameCount: AVAudioFrameCount(min(remaining, 4_096)))
            if pcm.frameLength == 0 { break }
            guard Double(frames + Int(pcm.frameLength)) / format.sampleRate <= MusicHapticTrack.maximumDuration else {
                throw MusicError.tooLong
            }
            let time = Double(frames) / format.sampleRate
            try decoder.append(pcm, at: time)
            frames += Int(pcm.frameLength)
            if time - lastProgress >= 0.25 {
                progress(0.1 + min(1, time / estimated) * 0.78,
                    "低音とビートを解析中 · \(musicTime(time))")
                lastProgress = time
            }
        }
        guard frames > 0, Double(frames) / format.sampleRate <= MusicHapticTrack.maximumDuration else {
            throw MusicError.tooLong
        }
        progress(0.9, "振動のトラックを作成しています")
        return try decoder.finish(hash: audioHash(url), useDecodedDuration: true)
    }

    private static func audioHash(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var digest = SHA256()
        while let bytes = try file.read(upToCount: 1_024 * 1_024), !bytes.isEmpty {
            try Task.checkCancellation()
            digest.update(data: bytes)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

final class MusicMediaDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Double, String) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var finished = false

    init(destination: URL, progress: @escaping @Sendable (Double, String) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func download(_ url: URL) async throws -> URL {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if finished {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 900
                configuration.urlCache = nil
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.downloadTask(with: url)
                self.task = task
                lock.unlock()
                task.resume()
            }
        }, onCancel: { self.finish(.failure(CancellationError())) })
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if max(totalBytesWritten, totalBytesExpectedToWrite) > MusicAnalyzer.maximumBytes {
            finish(.failure(MusicError.tooLong))
        } else {
            let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
            progress(fraction * 0.07, "初回解析用に読み込み中 · \(ByteCountFormatter.string(fromByteCount: totalBytesWritten, countStyle: .file))")
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                  response.url?.scheme == "https" else { throw MusicError.network("音源を取得できませんでした。URLの有効期限やアクセス権を確認してください。") }
            if response.mimeType?.lowercased().contains("text/html") == true {
                throw MusicError.network("このURLは音源ではなくWebページです。音声ファイルが直接返るダウンロードURLを指定してください。")
            }
            let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard Int64(size) <= MusicAnalyzer.maximumBytes else { throw MusicError.tooLong }
            finish(.success(destination), downloadedFile: location)
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>, downloadedFile: URL? = nil) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        var result = result
        if let downloadedFile {
            do { try FileManager.default.moveItem(at: downloadedFile, to: destination) }
            catch { result = .failure(error) }
        }
        let continuation = self.continuation, session = self.session, task = self.task
        self.continuation = nil
        self.session = nil
        self.task = nil
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
}
