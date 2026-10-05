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
}

// Bounded PCM buffer; channel energies are measured independently, including opposite-phase stereo.
final class MusicSignalExtractor {
    static let sampleRate = 22_050.0
    static let windowSize = 1_024
    static let hopSize = 441
    private let channels: Int
    private let setup: OpaquePointer
    private var window = [Float](repeating: 0, count: windowSize)
    private var pending: [Float] = []
    private var consumedFrames = 0
    private var totalFrames = 0
    private var previous: [[Float]]
    private var features: [MusicAudioFeature] = []

    init(channels: Int) throws {
        guard (1...8).contains(channels),
              let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(Self.windowSize), .FORWARD) else {
            throw MusicError.unsupportedMedia
        }
        self.channels = channels
        self.setup = setup
        previous = Array(repeating: Array(repeating: 0, count: Self.windowSize / 2), count: channels)
        vDSP_hann_window(&window, vDSP_Length(Self.windowSize), Int32(vDSP_HANN_NORM))
    }

    deinit { vDSP_DFT_DestroySetup(setup) }

    func append(_ interleavedSamples: [Float]) throws {
        guard interleavedSamples.count % channels == 0,
              interleavedSamples.allSatisfy({ $0.isFinite && abs($0) <= 16 }) else { throw MusicError.unsupportedMedia }
        totalFrames += interleavedSamples.count / channels
        guard Double(totalFrames) / Self.sampleRate <= MusicHapticTrack.maximumDuration + 0.1 else {
            throw MusicError.tooLong
        }
        pending.append(contentsOf: interleavedSamples)
        var readOffset = 0
        while pending.count - readOffset >= Self.windowSize * channels {
            try Task.checkCancellation()
            features.append(measure(offset: readOffset))
            readOffset += Self.hopSize * channels
            consumedFrames += Self.hopSize
        }
        if readOffset > 0 { pending.removeFirst(readOffset) }
    }

    func finish(hash: String) throws -> MusicHapticTrack {
        let duration = Double(totalFrames) / Self.sampleRate
        guard duration > 0 else { throw MusicError.unsupportedMedia }
        if !pending.isEmpty {
            pending.append(contentsOf: repeatElement(0, count: max(0, Self.windowSize * channels - pending.count)))
            features.append(measure(offset: 0))
        }
        return try Self.makeTrack(features: features, duration: duration, hash: hash)
    }

    private func measure(offset: Int) -> MusicAudioFeature {
        let n = Self.windowSize
        var rms = 0.0, bass = 0.0, flux = 0.0, centroid = 0.0
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
            var bassEnergy = 0.0, magnitudeSum = 0.0, weightedSum = 0.0, increase = 0.0
            for bin in 1..<(n / 2) {
                let magnitude = sqrt(outReal[bin] * outReal[bin] + outImaginary[bin] * outImaginary[bin])
                let frequency = Double(bin) * Self.sampleRate / Double(n)
                if (40...200).contains(frequency) { bassEnergy += Double(magnitude * magnitude) }
                if frequency <= 8_000 {
                    magnitudeSum += Double(magnitude)
                    weightedSum += Double(magnitude) * frequency
                    increase += Double(max(0, magnitude - previous[channel][bin]))
                }
                previous[channel][bin] = magnitude
            }
            rms += sqrt(energy / Double(n))
            bass += sqrt(bassEnergy) / Double(n)
            flux += increase / Double(n)
            centroid += magnitudeSum > 0 ? weightedSum / magnitudeSum / 6_000 : 0
        }
        let divisor = Double(channels)
        return MusicAudioFeature(time: Double(consumedFrames + n / 2) / Self.sampleRate,
                                 rms: rms / divisor, bass: bass / divisor,
                                 flux: flux / divisor, brightness: min(1, centroid / divisor))
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
        var envelope: [MusicEnvelopePoint] = []
        var taps: [MusicTap] = []
        var smoothBass = 0.0, smoothEnergy = 0.0
        for (index, frame) in frames.enumerated() {
            let audible = frame.rms > 0.000_03
            let bass = audible ? min(1, pow(frame.bass / bassScale, 0.7)) : 0
            let energy = audible ? min(1, pow(frame.rms / rmsScale, 0.7)) : 0
            smoothBass += (bass - smoothBass) * (bass > smoothBass ? 0.7 : 0.2)
            smoothEnergy += (energy - smoothEnergy) * (energy > smoothEnergy ? 0.65 : 0.2)
            // Silence is absolute; smoothing must never create vibration in silent sections.
            if !audible { smoothBass = 0; smoothEnergy = 0 }
            let sharpness = audible ? 0.15 + frame.brightness * 0.8 : 0
            envelope.append(.init(time: frame.time, bass: smoothBass, energy: smoothEnergy, sharpness: sharpness))
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
        envelope.insert(.init(time: 0, bass: first.bass, energy: first.energy, sharpness: first.sharpness), at: 0)
        envelope.append(.init(time: duration, bass: last.bass, energy: last.energy, sharpness: last.sharpness))
        return try MusicHapticTrack(version: MusicHapticTrack.currentVersion, audioSHA256: hash,
                                   duration: duration, envelope: envelope, taps: taps).validated()
    }
}

enum MusicAnalyzer {
    static let maximumBytes: Int64 = 512 * 1_024 * 1_024

    static func analyze(_ url: URL, progress: @escaping @Sendable (Double, String) -> Void) async throws -> MusicHapticTrack {
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
            AVSampleRateKey: MusicSignalExtractor.sampleRate,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw MusicError.unsupportedMedia }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? MusicError.unsupportedMedia }
        defer { reader.cancelReading() }
        var extractor: MusicSignalExtractor?
        var lastProgress = 0.0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let description = CMSampleBufferGetFormatDescription(sample),
                  let format = CMAudioFormatDescriptionGetStreamBasicDescription(description),
                  let block = CMSampleBufferGetDataBuffer(sample) else { throw MusicError.unsupportedMedia }
            if extractor == nil { extractor = try MusicSignalExtractor(channels: Int(format.pointee.mChannelsPerFrame)) }
            let bytes = CMBlockBufferGetDataLength(block)
            guard bytes % MemoryLayout<Float>.size == 0, bytes <= 8 * 1_024 * 1_024 else { throw MusicError.unsupportedMedia }
            var samples = [Float](repeating: 0, count: bytes / MemoryLayout<Float>.size)
            let status = samples.withUnsafeMutableBytes { buffer in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: buffer.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw MusicError.unsupportedMedia }
            try extractor?.append(samples)
            let position = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if position - lastProgress > 0.25 {
                progress(0.1 + min(1, position / duration) * 0.78, "低音とビートを解析中 · \(musicTime(position)) / \(musicTime(duration))")
                lastProgress = position
            }
        }
        guard reader.status == .completed, let extractor else { throw reader.error ?? MusicError.unsupportedMedia }
        progress(0.9, "振動のトラックを作成しています")
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var digest = SHA256()
        while let bytes = try file.read(upToCount: 1_024 * 1_024), !bytes.isEmpty {
            try Task.checkCancellation()
            digest.update(data: bytes)
        }
        let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
        return try extractor.finish(hash: hash)
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
            let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard Int64(size) <= MusicAnalyzer.maximumBytes else { throw MusicError.tooLong }
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
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
