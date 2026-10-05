import Foundation

enum MusicError: LocalizedError {
    case invalidURL, unsupportedMedia, tooLong, emptyAudio, corruptTrack, missingTrack
    case storage(String), network(String), account(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "YouTubeの動画URL、または音楽・動画ファイルのHTTPS URLを入力してください。"
        case .unsupportedMedia: return "解析できる音声がありません。保護されていないWAV・M4A・MP3・MP4などを選んでください。ライブ配信には対応していません。"
        case .tooLong: return "1曲20分以内、ファイル512 MB以内で選んでください。"
        case .emptyAudio: return "音源に振動を作れる音が見つかりませんでした。"
        case .corruptTrack: return "保存した振動を読み込めません。もう一度音源から作成してください。"
        case .missingTrack: return "この曲の振動はまだ作成されていません。"
        case .storage(let text), .network(let text), .account(let text): return text
        }
    }
}

struct MusicSelection: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case youtube, remote, file }
    let id: String
    let kind: Kind
    var title: String
    var artist: String
    let url: String
    var videoID: String?
    var duration: Double?

    static func youtube(id: String, title: String = "YouTube動画", artist: String = "") throws -> MusicSelection {
        guard validVideoID(id) else { throw MusicError.invalidURL }
        return MusicSelection(id: "youtube-\(id)", kind: .youtube, title: title,
                              artist: artist, url: "https://www.youtube.com/watch?v=\(id)", videoID: id)
    }

    static func file(_ url: URL) -> MusicSelection {
        MusicSelection(id: UUID().uuidString, kind: .file,
                       title: url.deletingPathExtension().lastPathComponent, artist: "読み込んだ音源", url: "")
    }

    static func parse(_ input: String) throws -> MusicSelection {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: text), components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil else { throw MusicError.invalidURL }
        let parts = components.path.split(separator: "/").map(String.init)
        if host == "youtu.be" || host == "www.youtu.be" {
            guard parts.count == 1 else { throw MusicError.invalidURL }
            return try youtube(id: parts[0])
        }
        if ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "www.youtube-nocookie.com"].contains(host) {
            let id: String?
            if components.path == "/watch" {
                id = components.queryItems?.first(where: { $0.name == "v" })?.value
            } else if parts.count == 2, ["shorts", "embed", "live"].contains(parts[0]) {
                id = parts[1]
            } else { id = nil }
            guard let id else { throw MusicError.invalidURL }
            return try youtube(id: id)
        }
        components.fragment = nil
        guard let url = components.url,
              ["wav", "m4a", "mp3", "mp4", "mov", "aac", "aiff", "aif", "caf"].contains(url.pathExtension.lowercased()) else {
            throw MusicError.invalidURL
        }
        // Identity includes signed query parameters; filenames never come from this value.
        return MusicSelection(id: "remote-\(url.absoluteString)", kind: .remote,
                              title: url.deletingPathExtension().lastPathComponent, artist: host, url: url.absoluteString)
    }

    static func validVideoID(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    }

    static func audioDownloadURL(_ input: String) throws -> URL {
        guard let components = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, let url = components.url,
              !host.lowercased().contains("youtube.com"), host.lowercased() != "youtu.be",
              !["html", "htm", "m3u8", "mpd"].contains(url.pathExtension.lowercased()) else { throw MusicError.invalidURL }
        return url
    }
}

struct MusicSettings: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable {
        case mix, beats, bass, energy
        var title: String {
            switch self {
            case .mix: return "ミックス"
            case .beats: return "ビート"
            case .bass: return "低音"
            case .energy: return "曲の強弱"
            }
        }
    }
    var mode: Mode = .mix
    var gain: Double = 0.7
    var bass: Double = 0.65
    var density: Double = 0.7
    // Positive values delay haptics relative to the video's media clock.
    var offset: Double = 0

    var normalized: MusicSettings {
        MusicSettings(mode: mode, gain: bounded(gain, to: 0...1, fallback: 0.7),
                      bass: bounded(bass, to: 0...1, fallback: 0.65),
                      density: bounded(density, to: 0...1, fallback: 0.7),
                      offset: bounded(offset, to: -1...1, fallback: 0))
    }

    func intensity(for point: MusicEnvelopePoint) -> Double {
        let level: Double
        switch mode {
        case .beats: level = 0
        case .bass: level = point.bass * bass * 0.65
        case .energy: level = point.energy * 0.55
        case .mix:
            if let mid = point.mid {
                level = point.bass * bass * 0.65 + mid * 0.20 + point.energy * 0.08
            } else { level = point.bass * bass * 0.5 + point.energy * 0.10 }
        }
        return min(1, max(0, level * gain))
    }

    func includes(_ tap: MusicTap) -> Bool {
        (mode == .mix || mode == .beats) && tap.intensity >= (1 - density) * 0.7
    }

    func sharpness(for point: MusicEnvelopePoint) -> Double {
        // Older tracks retain their original rendering; new tracks use the full mapped range.
        point.mid == nil ? point.sharpness * 0.65 : point.sharpness
    }
}

struct MusicRecord: Codable, Identifiable, Equatable {
    var selection: MusicSelection
    var createdAt = Date()
    var lastPlayedAt: Date?
    var trackFilename: String?
    var mediaFilename: String?
    var trackBytes: Int = 0
    var settings = MusicSettings()
    var analysis: MusicAnalysisInfo?
    var id: String { selection.id }
    var isPrepared: Bool { trackFilename != nil }
}

struct MusicEnvelopePoint: Codable, Equatable {
    let time: Double
    let bass: Double
    let energy: Double
    let sharpness: Double
    var mid: Double? = nil
    var high: Double? = nil
}

struct MusicSpectrumFrame: Codable, Equatable {
    let time: Double
    let levels: [Double]
}

enum MusicFrequencyBands {
    static let count = 24
    static let minimum = 20.0
    static let maximum = 8_000.0
    static let edges = (0...count).map { minimum * pow(maximum / minimum, Double($0) / Double(count)) }
    static let centers = (0..<count).map { sqrt(edges[$0] * edges[$0 + 1]) }

    static func index(for frequency: Double) -> Int? {
        guard frequency.isFinite, (minimum...maximum).contains(frequency) else { return nil }
        return min(count - 1, Int(log(frequency / minimum) / log(maximum / minimum) * Double(count)))
    }
}

struct MusicHapticOutput {
    let continuous: Double
    let sharpness: Double
    let transient: Double
    var level: Double { max(continuous, transient) }
}

struct MusicTap: Codable, Equatable {
    let time: Double
    let intensity: Double
    let sharpness: Double
}

struct MusicHapticTrack: Codable, Equatable {
    static let currentVersion = 2
    static let maximumDuration = 1_200.0
    let version: Int
    let audioSHA256: String
    let duration: Double
    let envelope: [MusicEnvelopePoint]
    let taps: [MusicTap]
    var analysis: MusicAnalysisInfo? = nil
    var spectrum: [MusicSpectrumFrame]? = nil

    func validated() throws -> MusicHapticTrack {
        guard (1...Self.currentVersion).contains(version), duration.isFinite, duration > 0,
              duration <= Self.maximumDuration,
              audioSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              !envelope.isEmpty, envelope.count <= 125_000, taps.count <= 12_001 else {
            throw MusicError.corruptTrack
        }
        if let analysis {
            guard ["device", "pc"].contains(analysis.engine), analysis.elapsedSeconds.isFinite,
                  (0...86_400).contains(analysis.elapsedSeconds), (8_000...192_000).contains(analysis.sampleRate),
                  analysis.hopMilliseconds.isFinite, (1...100).contains(analysis.hopMilliseconds),
                  (128...16_384).contains(analysis.fftSize),
                  analysis.serverTrackID == nil || analysis.serverTrackID?.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                throw MusicError.corruptTrack
            }
        }
        var previous = -Double.infinity
        for point in envelope {
            guard point.time.isFinite, point.time > previous, (0...duration).contains(point.time),
                  ([point.bass, point.energy, point.sharpness] + [point.mid, point.high].compactMap { $0 })
                    .allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                throw MusicError.corruptTrack
            }
            previous = point.time
        }
        previous = -Double.infinity
        for tap in taps {
            guard tap.time.isFinite, tap.time > previous, (0..<duration).contains(tap.time),
                  [tap.intensity, tap.sharpness].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                throw MusicError.corruptTrack
            }
            previous = tap.time
        }
        if let spectrum {
            guard !spectrum.isEmpty, spectrum.count <= 125_000 else { throw MusicError.corruptTrack }
            previous = -Double.infinity
            for frame in spectrum {
                guard frame.time.isFinite, frame.time > previous, (0...duration).contains(frame.time),
                      frame.levels.count == MusicFrequencyBands.count,
                      frame.levels.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw MusicError.corruptTrack }
                previous = frame.time
            }
        }
        return self
    }

    func value(at time: Double) -> MusicEnvelopePoint {
        let index = lowerBound(envelope, time: time, key: { $0.time })
        if index == 0 || index == envelope.count {
            let point = index == 0 ? envelope[0] : envelope[envelope.count - 1]
            return MusicEnvelopePoint(time: time, bass: point.bass, energy: point.energy, sharpness: point.sharpness,
                                      mid: point.mid, high: point.high)
        }
        let left = envelope[index - 1], right = envelope[index]
        let fraction = bounded((time - left.time) / (right.time - left.time), to: 0...1, fallback: 0)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * fraction }
        return MusicEnvelopePoint(time: time, bass: mix(left.bass, right.bass),
                                  energy: mix(left.energy, right.energy), sharpness: mix(left.sharpness, right.sharpness),
                                  mid: left.mid.flatMap { a in right.mid.map { mix(a, $0) } },
                                  high: left.high.flatMap { a in right.high.map { mix(a, $0) } })
    }

    func spectrum(at time: Double) -> [Double]? {
        guard let spectrum, !spectrum.isEmpty else { return nil }
        guard time >= 0, time < duration else { return Array(repeating: 0, count: MusicFrequencyBands.count) }
        let index = lowerBound(spectrum, time: time, key: { $0.time })
        if index == 0 { return spectrum[0].levels }
        if index == spectrum.count { return spectrum[spectrum.count - 1].levels }
        let left = spectrum[index - 1], right = spectrum[index]
        let fraction = bounded((time - left.time) / (right.time - left.time), to: 0...1, fallback: 0)
        return zip(left.levels, right.levels).map { $0 + ($1 - $0) * fraction }
    }

    // The UI reads the same mapping and tap filter used by segment(). Never anticipate future taps.
    func output(at time: Double, settings: MusicSettings) -> MusicHapticOutput {
        guard time.isFinite, time >= 0, time < duration else { return .init(continuous: 0, sharpness: 0, transient: 0) }
        let settings = settings.normalized
        let point = value(at: time)
        let first = lowerBound(taps, time: max(0, time - 0.06), key: { $0.time })
        let last = lowerBound(taps, time: time + 0.000_000_1, key: { $0.time })
        var transient: Double = 0
        for tap in taps[first..<last] where settings.includes(tap) {
            let elapsed: Double = max(0, time - tap.time)
            let decay: Double = max(0, 1 - elapsed / 0.06)
            let intensity: Double = tap.intensity * settings.gain * decay
            transient = max(transient, intensity)
        }
        return .init(continuous: settings.intensity(for: point), sharpness: settings.sharpness(for: point), transient: transient)
    }

    // Tap intervals are half-open, so a tap at a chunk boundary plays exactly once.
    // Continuous and transient tracks use separate players to avoid multiplying taps by the bass curve.
    func segment(at start: Double, length: Double, rate: Double = 1,
                 settings: MusicSettings = MusicSettings()) -> [HapticPatternSpec] {
        guard start.isFinite, start >= 0, start < duration, length.isFinite, length > 0,
              rate.isFinite, (0.25...2).contains(rate), !envelope.isEmpty else { return [] }
        let end = min(duration, start + min(length, 2))
        let span = (end - start) / rate
        let settings = settings.normalized
        var result: [HapticPatternSpec] = []
        if settings.mode != .beats {
            let first = lowerBound(envelope, time: start, key: { $0.time })
            let last = lowerBound(envelope, time: end, key: { $0.time })
            var points = [value(at: start)]
            points.append(contentsOf: envelope[first..<last].filter { $0.time > start })
            points.append(value(at: end))
            func intensity(_ point: MusicEnvelopePoint) -> Double {
                settings.intensity(for: point)
            }
            if points.contains(where: { intensity($0) > 0.001 }) {
                var curves: [HapticCurveSpec] = []
                var offset = 0
                while offset < points.count - 1 {
                    let limit = min(points.count, offset + 16)
                    let slice = points[offset..<limit]
                    curves.append(HapticCurveSpec(parameter: .intensity, points: slice.map {
                        .init(time: ($0.time - start) / rate, value: intensity($0))
                    }))
                    curves.append(HapticCurveSpec(parameter: .sharpness, points: slice.map {
                        .init(time: ($0.time - start) / rate, value: settings.sharpness(for: $0))
                    }))
                    offset = limit - 1
                }
                result.append(HapticPatternSpec(id: "music-bed", name: "音楽 · 持続", subtitle: "", symbol: "waveform",
                    category: "music", duration: span,
                    events: [.init(kind: .continuous, time: 0, duration: span, intensity: 1, sharpness: 0)], curves: curves))
            }
        }
        if settings.mode == .mix || settings.mode == .beats {
            let first = lowerBound(taps, time: start, key: { $0.time })
            let last = lowerBound(taps, time: end, key: { $0.time })
            let events = taps[first..<last].filter { settings.includes($0) }.map {
                HapticEventSpec(kind: .tap, time: ($0.time - start) / rate, duration: 0,
                                intensity: $0.intensity * settings.gain, sharpness: $0.sharpness)
            }
            if !events.isEmpty {
                result.append(HapticPatternSpec(id: "music-taps", name: "音楽 · ビート", subtitle: "", symbol: "waveform",
                                               category: "music", duration: span, events: events, curves: []))
            }
        }
        return result
    }
}

func lowerBound<T>(_ values: [T], time: Double, key: (T) -> Double) -> Int {
    var low = 0, high = values.count
    while low < high {
        let middle = (low + high) / 2
        if key(values[middle]) < time { low = middle + 1 } else { high = middle }
    }
    return low
}

// Require the media clock to advance, even when a player reports "playing" during a stall.
struct MusicPlaybackGate {
    private var previousPosition: Double?
    private var lastAdvance = 0.0
    private var previousHost = -Double.infinity

    mutating func accept(position: Double, playing: Bool, rate: Double, hostTime: Double) -> Bool {
        guard playing, position.isFinite, position >= 0, rate.isFinite, (0.25...2).contains(rate),
              hostTime.isFinite, hostTime >= previousHost else { reset(); return false }
        previousHost = hostTime
        if let previousPosition, abs(position - previousPosition) < 0.001 {
            return hostTime - lastAdvance <= 0.25
        }
        previousPosition = position
        lastAdvance = hostTime
        return true
    }

    mutating func reset() { previousPosition = nil; lastAdvance = 0; previousHost = -Double.infinity }
}

struct MusicMediaClock {
    private var gate = MusicPlaybackGate()
    private var anchorPosition = 0.0
    private var anchorHost = 0.0
    private var rate = 0.0
    private var previousSource: Double?

    mutating func update(position: Double, playing: Bool, rate: Double, hostTime: Double, clockPosition: Double? = nil) {
        guard position.isFinite, position >= 0, hostTime.isFinite else { reset(); return }
        let source = clockPosition ?? position
        let accepted = gate.accept(position: source, playing: playing, rate: rate, hostTime: hostTime)
        // Some iframe snapshots repeat a quantized timestamp. Keep interpolating from
        // the last advancing sample instead of jumping back on each repeated snapshot.
        if !accepted || previousSource == nil || abs(source - (previousSource ?? source)) >= 0.001 || self.rate != rate {
            anchorPosition = position
            anchorHost = hostTime
        }
        previousSource = source
        self.rate = accepted ? rate : 0
    }

    func position(at hostTime: Double) -> Double {
        guard hostTime.isFinite else { return anchorPosition }
        // Never invent continued playback when the media clock stops reporting progress.
        return anchorPosition + min(0.25, max(0, hostTime - anchorHost)) * rate
    }

    mutating func reset(to position: Double = 0) {
        gate.reset()
        anchorPosition = position
        anchorHost = 0
        rate = 0
        previousSource = nil
    }
}

func musicTime(_ seconds: Double) -> String {
    let value = seconds.isFinite ? max(0, Int(min(seconds, 315_360_000))) : 0
    return String(format: "%d:%02d", value / 60, value % 60)
}
