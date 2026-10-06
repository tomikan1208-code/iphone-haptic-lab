import AVFoundation

// Keep decoder timestamps in the source sample rate. Resample PCM explicitly,
// using frameLength rather than the size/capacity of its backing allocation.
final class MusicPCMDecoder {
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private let extractor: MusicSignalExtractor
    private let duration: Double
    private let maximumOutputFrames: Int
    private var sourceFrames = 0
    private var outputFrames = 0

    init(format: AVAudioFormat, duration: Double, quality: MusicAnalysisQuality = .standard) throws {
        guard format.commonFormat == .pcmFormatFloat32,
              format.sampleRate.isFinite, (8_000...192_000).contains(format.sampleRate),
              (1...8).contains(format.channelCount), duration.isFinite, duration > 0,
              duration <= MusicHapticTrack.maximumDuration,
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                  sampleRate: quality.sampleRate, channels: format.channelCount, interleaved: false),
              let converter = AVAudioConverter(from: format, to: output) else { throw MusicError.unsupportedMedia }
        inputFormat = format
        outputFormat = output
        self.converter = converter
        self.duration = duration
        maximumOutputFrames = Int((duration * quality.sampleRate).rounded())
        extractor = try MusicSignalExtractor(channels: Int(format.channelCount), quality: quality)
    }

    func append(_ buffer: AVAudioPCMBuffer, at time: Double) throws {
        guard buffer.format.isEqual(inputFormat), time.isFinite,
              abs(time) <= MusicHapticTrack.maximumDuration + 1 else { throw MusicError.unsupportedMedia }
        let position = Int((time * inputFormat.sampleRate).rounded())
        let gap = position - sourceFrames
        if gap > 0 {
            try checkSourceEnd(position)
            var remaining = gap
            while remaining > 0 {
                let count = min(4_096, remaining)
                guard let silence = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(count)),
                      let planes = silence.floatChannelData else { throw MusicError.unsupportedMedia }
                silence.frameLength = AVAudioFrameCount(count)
                for channel in 0..<(inputFormat.isInterleaved ? 1 : Int(inputFormat.channelCount)) {
                    planes[channel].initialize(repeating: 0, count: count * silence.stride)
                }
                try convert(silence)
                sourceFrames += count
                remaining -= count
            }
        }
        let skipped = max(0, -gap)
        let count = Int(buffer.frameLength) - skipped
        guard count > 0 else { return }
        try checkSourceEnd(sourceFrames + count)
        if skipped == 0 { try convert(buffer) }
        else {
            guard let clipped = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(count)),
                  let source = buffer.floatChannelData, let destination = clipped.floatChannelData else {
                throw MusicError.unsupportedMedia
            }
            clipped.frameLength = AVAudioFrameCount(count)
            for channel in 0..<(inputFormat.isInterleaved ? 1 : Int(inputFormat.channelCount)) {
                destination[channel].update(from: source[channel] + skipped * buffer.stride, count: count * buffer.stride)
            }
            try convert(clipped)
        }
        sourceFrames += count
    }

    func finish(hash: String, useDecodedDuration: Bool = false) throws -> MusicHapticTrack {
        try convert(nil)
        let end = useDecodedDuration ? Double(sourceFrames) / inputFormat.sampleRate : duration
        return try extractor.finish(hash: hash, expectedDuration: end)
    }

    private func checkSourceEnd(_ frames: Int) throws {
        guard Double(frames) / inputFormat.sampleRate <= duration + 0.1 else {
            throw MusicError.storage("音声のサンプル数と再生時間が一致しません。誤った振動を保存せず停止しました。")
        }
    }

    private func convert(_ input: AVAudioPCMBuffer?) throws {
        var supplied = false
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4_096) else {
            throw MusicError.unsupportedMedia
        }
        while true {
            try Task.checkCancellation()
            var error: NSError?
            output.frameLength = 0
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if let input, !supplied {
                    supplied = true
                    inputStatus.pointee = .haveData
                    return input
                }
                inputStatus.pointee = input == nil ? .endOfStream : .noDataNow
                return nil
            }
            if status == .error { throw (error as Error?) ?? MusicError.unsupportedMedia }
            let count = Int(output.frameLength)
            guard outputFrames + count <= maximumOutputFrames + Int(outputFormat.sampleRate * 0.1) else {
                throw MusicError.storage("変換後の音声が本来の長さを超えました。誤った振動を保存せず停止しました。")
            }
            let valid = min(count, max(0, maximumOutputFrames - outputFrames))
            if valid > 0 {
                guard let channels = output.floatChannelData else { throw MusicError.unsupportedMedia }
                var samples = [Float]()
                samples.reserveCapacity(valid * Int(outputFormat.channelCount))
                for frame in 0..<valid {
                    for channel in 0..<Int(outputFormat.channelCount) { samples.append(channels[channel][frame]) }
                }
                try extractor.append(samples)
            }
            outputFrames += count
            if status == .endOfStream || status == .inputRanDry { return }
            guard count > 0 else { throw MusicError.unsupportedMedia }
        }
    }
}
