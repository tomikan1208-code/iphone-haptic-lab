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
    static let gainRange = 0.0...4.0
    var gain: Double = 0.7
    var bass: Double = 0.65
    var density: Double = 0.7
    // Positive values delay haptics relative to the video's media clock.
    var offset: Double = 0
    var continuousGain: Double = 1
    var transientGain: Double = 1
    // 0.5 preserves each recorded tap; lower values soften it, higher values sharpen it.
    var transientSharpness: Double = 0.5

    private enum CodingKeys: String, CodingKey {
        case mode, gain, bass, density, offset, continuousGain, transientGain, transientSharpness
    }

    var normalized: MusicSettings {
        MusicSettings(mode: mode, gain: bounded(gain, to: Self.gainRange, fallback: 0.7),
                      bass: bounded(bass, to: 0...1, fallback: 0.65),
                      density: bounded(density, to: 0...1, fallback: 0.7),
                      offset: bounded(offset, to: -1...1, fallback: 0),
                      continuousGain: bounded(continuousGain, to: 0...1, fallback: 1),
                      transientGain: bounded(transientGain, to: 0...1, fallback: 1),
                      transientSharpness: bounded(transientSharpness, to: 0...1, fallback: 0.5))
    }

    func intensity(for point: MusicEnvelopePoint) -> Double {
        if let composed = point.intensity {
            return mode == .beats ? 0 : amplified(composed * bounded(continuousGain, to: 0...1, fallback: 1))
        }
        let level: Double
        switch mode {
        case .beats: level = 0
        case .bass: level = point.bass * bass * 0.65
        case .energy: level = point.energy * 0.55
        case .mix:
            if point.texture != nil {
                level = point.bass * bass * 0.65 + point.energy * 0.08
            } else if let mid = point.mid {
                level = point.bass * bass * 0.65 + mid * 0.20 + point.energy * 0.08
            } else { level = point.bass * bass * 0.5 + point.energy * 0.10 }
        }
        return amplified(level * bounded(continuousGain, to: 0...1, fallback: 1))
    }

    // Amplify saved dynamics while keeping every hardware event and visual inside 0...1.
    func amplified(_ intensity: Double) -> Double {
        bounded(intensity * bounded(gain, to: Self.gainRange, fallback: 0.7), to: 0...1, fallback: 0)
    }

    func includes(_ tap: MusicTap) -> Bool {
        (mode == .mix || mode == .beats) && transientGain > 0
            && (tap.priority ?? tap.intensity) >= (1 - density) * 0.7
    }

    func intensity(for tap: MusicTap) -> Double {
        amplified(tap.intensity * bounded(transientGain, to: 0...1, fallback: 1))
    }

    func sharpness(for tap: MusicTap) -> Double {
        let source = bounded(tap.sharpness, to: 0...1, fallback: 0.5)
        let control = bounded(transientSharpness, to: 0...1, fallback: 0.5)
        if control <= 0.5 { return source * control * 2 }
        return source + (1 - source) * (control - 0.5) * 2
    }

    mutating func emphasizeTaps() {
        mode = .mix
        gain = 0.8
        continuousGain = 0.25
        transientGain = 1
        transientSharpness = 0.9
        density = 1
    }

    func sharpness(for point: MusicEnvelopePoint) -> Double {
        // Older tracks retain their original rendering; new tracks use the full mapped range.
        point.mid == nil ? point.sharpness * 0.65 : point.sharpness
    }
}

extension MusicSettings {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(mode: try values.decodeIfPresent(Mode.self, forKey: .mode) ?? .mix,
                  gain: try values.decodeIfPresent(Double.self, forKey: .gain) ?? 0.7,
                  bass: try values.decodeIfPresent(Double.self, forKey: .bass) ?? 0.65,
                  density: try values.decodeIfPresent(Double.self, forKey: .density) ?? 0.7,
                  offset: try values.decodeIfPresent(Double.self, forKey: .offset) ?? 0,
                  continuousGain: try values.decodeIfPresent(Double.self, forKey: .continuousGain) ?? 1,
                  transientGain: try values.decodeIfPresent(Double.self, forKey: .transientGain) ?? 1,
                  transientSharpness: try values.decodeIfPresent(Double.self, forKey: .transientSharpness) ?? 0.5)
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
    var requiresAudioReanalysis: Bool {
        isPrepared && selection.kind == .youtube && (analysis == nil || analysis?.engine == "device")
            && (analysis?.decoderVersion ?? 0) < MusicAnalyzer.decoderVersion
    }
}

struct MusicEnvelopePoint: Codable, Equatable {
    let time: Double
    let bass: Double
    let energy: Double
    let sharpness: Double
    var mid: Double? = nil
    var high: Double? = nil
    var texture: MusicLowTexture? = nil
    // Version 3 stores the arranged voice directly; source energies are visualization data.
    var intensity: Double? = nil
}

struct MusicLowTexture: Codable, Equatable {
    let sub: Double
    let kick: Double
    let body: Double
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
    var role: String? = nil
    var priority: Double? = nil
}

struct MusicArrangementScore: Codable, Equatable {
    struct Section: Codable, Equatable, Identifiable {
        let id: String
        let start: Double
        let end: Double
        let label: String
        let confidence: Double
        let mood: String
        let family: String
    }
    struct Bar: Codable, Equatable {
        let start: Double
        let end: Double
        let meter: Int
        let sectionID: String
        let motif: String
        let reliable: Bool
    }
    let version: Int
    let sections: [Section]
    let bars: [Bar]
    let rhythmAgreement: Double
    let rhythmSource: String

    func validated(duration: Double) throws {
        guard version == 1, !sections.isEmpty, sections.count <= 512, bars.count <= 4_000,
              rhythmAgreement.isFinite, (0...1).contains(rhythmAgreement),
              ["all-in-one", "beat-this"].contains(rhythmSource),
              Set(sections.map(\.id)).count == sections.count else { throw MusicError.corruptTrack }
        var previous = 0.0
        for section in sections {
            guard section.start.isFinite, section.end.isFinite,
                  section.start >= previous, section.end > section.start, section.end <= duration,
                  section.confidence.isFinite, (0...1).contains(section.confidence),
                  section.id.count <= 64, section.label.count <= 32,
                  section.mood.count <= 32, section.family.count <= 32 else { throw MusicError.corruptTrack }
            previous = section.end
        }
        previous = 0
        for bar in bars {
            guard bar.start.isFinite, bar.end.isFinite, bar.start >= previous,
                  bar.end > bar.start, bar.end <= duration, (2...7).contains(bar.meter),
                  sections.contains(where: { $0.id == bar.sectionID }),
                  ["sparse", "pulse", "drive", "offbeat", "breath", "rest"].contains(bar.motif)
            else { throw MusicError.corruptTrack }
            previous = bar.end
        }
    }
}

struct MusicHapticTrack: Codable, Equatable {
    static let currentVersion = 3
    static let maximumDuration = 1_200.0
    let version: Int
    let audioSHA256: String
    let duration: Double
    let envelope: [MusicEnvelopePoint]
    let taps: [MusicTap]
    var analysis: MusicAnalysisInfo? = nil
    var spectrum: [MusicSpectrumFrame]? = nil
    var arrangement: MusicArrangementScore? = nil

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
                  analysis.processingSeconds.map({ $0.isFinite && (0...86_400).contains($0) }) ?? true,
                  analysis.serverTrackID == nil || analysis.serverTrackID?.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                throw MusicError.corruptTrack
            }
        }
        if version == 3 {
            guard arrangement != nil, envelope.allSatisfy({ $0.intensity != nil }) else { throw MusicError.corruptTrack }
        }
        if let arrangement { try arrangement.validated(duration: duration) }
        var previous = -Double.infinity
        for point in envelope {
            guard point.time.isFinite, point.time > previous, (0...duration).contains(point.time),
                  ([point.bass, point.energy, point.sharpness] + [point.mid, point.high, point.intensity].compactMap { $0 }
                   + (point.texture.map { [$0.sub, $0.kick, $0.body] } ?? []))
                    .allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                throw MusicError.corruptTrack
            }
            previous = point.time
        }
        previous = -Double.infinity
        for tap in taps {
            guard tap.time.isFinite, tap.time > previous, (0..<duration).contains(tap.time),
                  ([tap.intensity, tap.sharpness] + [tap.priority].compactMap { $0 })
                    .allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  tap.role.map({ ["accent", "groove", "fill"].contains($0) }) ?? true else {
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
                                      mid: point.mid, high: point.high, texture: point.texture, intensity: point.intensity)
        }
        let left = envelope[index - 1], right = envelope[index]
        let fraction = bounded((time - left.time) / (right.time - left.time), to: 0...1, fallback: 0)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * fraction }
        return MusicEnvelopePoint(time: time, bass: mix(left.bass, right.bass),
                                  energy: mix(left.energy, right.energy), sharpness: mix(left.sharpness, right.sharpness),
                                  mid: left.mid.flatMap { a in right.mid.map { mix(a, $0) } },
                                  high: left.high.flatMap { a in right.high.map { mix(a, $0) } },
                                  texture: left.texture.flatMap { a in right.texture.map {
                                      .init(sub: mix(a.sub, $0.sub), kick: mix(a.kick, $0.kick), body: mix(a.body, $0.body))
                                  } }, intensity: left.intensity.flatMap { a in right.intensity.map { mix(a, $0) } })
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
    private func continuousIntensity(at time: Double, settings: MusicSettings) -> Double {
        guard !envelope.isEmpty else { return 0 }
        let index = lowerBound(envelope, time: time, key: { $0.time })
        if index == 0 { return settings.intensity(for: envelope[0]) }
        if index == envelope.count { return settings.intensity(for: envelope[envelope.count - 1]) }
        let left = envelope[index - 1], right = envelope[index]
        let fraction = bounded((time - left.time) / (right.time - left.time), to: 0...1, fallback: 0)
        // Hardware interpolates the clipped control points, not the unclipped source envelope.
        let from = settings.intensity(for: left), to = settings.intensity(for: right)
        return from + (to - from) * fraction
    }

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
            let intensity: Double = settings.intensity(for: tap) * decay
            transient = max(transient, intensity)
        }
        return .init(continuous: continuousIntensity(at: time, settings: settings), sharpness: settings.sharpness(for: point), transient: transient)
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
                continuousIntensity(at: point.time, settings: settings)
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
                                intensity: settings.intensity(for: $0), sharpness: settings.sharpness(for: $0))
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

// A transient iframe duration must silence haptics immediately, without declaring
// that the saved audio is wrong. Confirm a diagnostic only during stable playback.
struct MusicDurationGate {
    enum Result: Equatable { case waiting, matching, different }
    private var candidate: Double?
    private var since = 0.0

    mutating func check(duration: Double, expected: Double, playing: Bool, hostTime: Double) -> Result {
        guard duration.isFinite, duration > 0, expected.isFinite, expected > 0,
              hostTime.isFinite else { reset(); return .waiting }
        if abs(duration - expected) <= max(1, expected * 0.015) {
            reset()
            return .matching
        }
        guard playing else { reset(); return .waiting }
        if candidate == nil || abs(duration - (candidate ?? 0)) > 0.1 || hostTime < since {
            candidate = duration
            since = hostTime
        }
        return hostTime - since >= 1 ? .different : .waiting
    }

    mutating func reset() { candidate = nil; since = 0 }
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
