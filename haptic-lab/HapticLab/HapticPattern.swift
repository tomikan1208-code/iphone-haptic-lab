import Foundation

enum HapticKind: String, Codable, CaseIterable {
    case tap
    case continuous
    case pulses

    var title: String {
        switch self {
        case .tap: return "一瞬"
        case .continuous: return "持続"
        case .pulses: return "連打"
        }
    }
}

struct HapticEventSpec: Codable, Equatable {
    let kind: HapticKind
    let time: Double
    let duration: Double
    let intensity: Double
    let sharpness: Double
}

struct HapticCurveSpec: Codable, Equatable {
    enum Parameter: String, Codable {
        case intensity
        case sharpness
    }

    struct Point: Codable, Equatable {
        let time: Double
        let value: Double
    }

    let parameter: Parameter
    let points: [Point]
}

struct HapticPatternSpec: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let symbol: String
    let category: String
    let duration: Double
    let events: [HapticEventSpec]
    let curves: [HapticCurveSpec]

    func validated() throws -> HapticPatternSpec {
        guard !id.isEmpty, !name.isEmpty,
              duration.isFinite, duration > 0, duration <= 30,
              !events.isEmpty, events.count <= 256 else {
            throw PatternError.invalid("名前・長さ・イベント数を確認してください。")
        }

        for event in events {
            guard event.kind != .pulses,
                  event.time.isFinite, event.time >= 0, event.time <= duration,
                  event.intensity.isFinite, (0...1).contains(event.intensity),
                  event.sharpness.isFinite, (0...1).contains(event.sharpness),
                  event.duration.isFinite else {
                throw PatternError.invalid("振動の強さ・鋭さ・時刻が範囲外です。")
            }
            if event.kind == .continuous {
                guard event.duration > 0, event.duration <= 30,
                      event.time + event.duration <= duration + 0.000_001 else {
                    throw PatternError.invalid("持続する振動は1回30秒以内にしてください。")
                }
            } else if event.duration != 0 {
                throw PatternError.invalid("一瞬の振動には持続時間を設定できません。")
            }
        }

        for curve in curves {
            guard (2...16).contains(curve.points.count) else {
                throw PatternError.invalid("強弱の変化点は2〜16個にしてください。")
            }
            var previousTime = -Double.infinity
            for point in curve.points {
                guard point.time.isFinite, point.time >= 0, point.time <= duration,
                      point.time > previousTime,
                      point.value.isFinite, (0...1).contains(point.value) else {
                    throw PatternError.invalid("強弱の変化点は時刻順に設定してください。")
                }
                previousTime = point.time
            }
        }
        return self
    }
}

enum PatternError: LocalizedError {
    case invalid(String)
    case missingCatalog

    var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .missingCatalog: return "触感の見本を読み込めませんでした。"
        }
    }
}

enum PatternCatalog {
    static func load(bundle: Bundle = .main) throws -> [HapticPatternSpec] {
        guard let url = bundle.url(forResource: "Presets", withExtension: "json") else {
            throw PatternError.missingCatalog
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> [HapticPatternSpec] {
        let patterns = try JSONDecoder().decode([HapticPatternSpec].self, from: data)
        guard !patterns.isEmpty, Set(patterns.map(\.id)).count == patterns.count else {
            throw PatternError.invalid("見本のIDが重複しているか、見本がありません。")
        }
        return try patterns.map { try $0.validated() }
    }
}

struct ExperimentConfiguration {
    var kind: HapticKind = .continuous
    var intensity: Double = 0.65
    var sharpness: Double = 0.5
    var duration: Double = 1.5
    var interval: Double = 0.2

    static func saved(defaults: UserDefaults = .standard) -> ExperimentConfiguration {
        func number(_ key: String, fallback: Double) -> Double {
            defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
        }
        return ExperimentConfiguration(
            kind: HapticKind(rawValue: defaults.string(forKey: "experiment.kind") ?? "") ?? .continuous,
            intensity: number("experiment.intensity", fallback: 0.65),
            sharpness: number("experiment.sharpness", fallback: 0.5),
            duration: number("experiment.duration", fallback: 1.5),
            interval: number("experiment.interval", fallback: 0.2)
        ).normalized
    }

    var normalized: ExperimentConfiguration {
        ExperimentConfiguration(
            kind: kind,
            intensity: bounded(intensity, to: 0...1, fallback: 0.65),
            sharpness: bounded(sharpness, to: 0...1, fallback: 0.5),
            duration: bounded(duration, to: 0.1...5, fallback: 1.5),
            interval: bounded(interval, to: 0.08...0.8, fallback: 0.2)
        )
    }
}

func bounded(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
    guard value.isFinite else { return fallback }
    return min(range.upperBound, max(range.lowerBound, value))
}

enum PatternFactory {
    static func experiment(_ configuration: ExperimentConfiguration) -> HapticPatternSpec {
        let settings = configuration.normalized
        let events: [HapticEventSpec]
        let duration: Double
        switch settings.kind {
        case .tap:
            duration = 0.1
            events = [HapticEventSpec(kind: .tap, time: 0, duration: 0,
                                      intensity: settings.intensity, sharpness: settings.sharpness)]
        case .continuous:
            duration = settings.duration
            events = [HapticEventSpec(kind: .continuous, time: 0, duration: duration,
                                      intensity: settings.intensity, sharpness: settings.sharpness)]
        case .pulses:
            duration = settings.duration
            events = stride(from: 0.0, to: duration, by: settings.interval).map {
                HapticEventSpec(kind: .tap, time: $0, duration: 0,
                                intensity: settings.intensity, sharpness: settings.sharpness)
            }
        }
        return HapticPatternSpec(id: "experiment", name: "自分で作った触感", subtitle: "",
                                 symbol: "slider.horizontal.3", category: "custom", duration: duration,
                                 events: events, curves: [])
    }

    static func metronome(bpm: Double, intensity: Double, sharpness: Double) -> HapticPatternSpec {
        let tempo = bounded(bpm, to: 40...200, fallback: 100)
        let strength = bounded(intensity, to: 0...1, fallback: 0.65)
        let crispness = bounded(sharpness, to: 0...1, fallback: 0.5)
        let beat = 60 / tempo
        let duration = beat * 4
        var events = (0..<4).map { index in
            HapticEventSpec(kind: .tap, time: Double(index) * beat, duration: 0,
                            intensity: index == 0 ? strength : strength * 0.55,
                            sharpness: crispness)
        }
        // A silent event keeps the fourth beat's trailing gap inside the loop.
        events.append(HapticEventSpec(kind: .continuous, time: 0, duration: duration,
                                      intensity: 0, sharpness: 0))
        return HapticPatternSpec(id: "metronome", name: "リズム · \(Int(tempo)) BPM", subtitle: "",
                                 symbol: "metronome", category: "rhythm", duration: duration,
                                 events: events, curves: [])
    }
}
