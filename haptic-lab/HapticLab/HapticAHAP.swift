import CoreHaptics
import CoreFoundation
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// AHAP is an interchange format. Native validation additionally checks Apple's parameter IDs.
struct HapticAHAP {
    let dictionary: [String: Any]
    let duration: Double
    let containsAudio: Bool

    init(data: Data) throws {
        guard data.count <= 2 * 1_024 * 1_024,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = root["Version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let entries = root["Pattern"] as? [[String: Any]], !entries.isEmpty, entries.count <= 1_024 else {
            throw PatternError.invalid("Version 1のAHAPファイルを選んでください（2 MB以内）。")
        }
        var end = 0.0, audio = false, events = 0
        func number(_ value: Any?) throws -> Double {
            guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite else { throw PatternError.invalid("AHAPの数値が不正です。") }
            return value.doubleValue
        }
        for entry in entries {
            guard ["Event", "Parameter", "ParameterCurve"].filter({ entry[$0] != nil }).count == 1 else {
                throw PatternError.invalid("AHAPの各要素にはEvent、Parameter、ParameterCurveのいずれか1つが必要です。")
            }
            if let event = entry["Event"] as? [String: Any] {
                events += 1
                let time = try number(event["Time"])
                guard time >= 0, let type = event["EventType"] as? String,
                      ["HapticTransient", "HapticContinuous", "AudioContinuous"].contains(type) else {
                    throw PatternError.invalid("振動・合成音のAHAPに対応しています。外部音声ファイルの参照は使えません。")
                }
                let length = try event["EventDuration"].map { try number($0) } ?? 0
                guard length >= 0, (type == "HapticTransient" ? length == 0 : length > 0) else {
                    throw PatternError.invalid("AHAPのイベント長が不正です。")
                }
                for parameter in event["EventParameters"] as? [[String: Any]] ?? [] {
                    _ = try number(parameter["ParameterValue"])
                }
                audio = audio || type == "AudioContinuous"
                end = max(end, time + length)
            } else if let parameter = entry["Parameter"] as? [String: Any] {
                let time = try number(parameter["Time"])
                _ = try number(parameter["ParameterValue"])
                guard time >= 0 else { throw PatternError.invalid("AHAPの時刻が不正です。") }
                end = max(end, time)
            } else if let curve = entry["ParameterCurve"] as? [String: Any] {
                let time = try number(curve["Time"])
                guard time >= 0, let points = curve["ParameterCurveControlPoints"] as? [[String: Any]],
                      (1...16).contains(points.count) else { throw PatternError.invalid("AHAPの変化点が不正です。") }
                var previous = -Double.infinity
                for point in points {
                    let offset = try number(point["Time"])
                    _ = try number(point["ParameterValue"])
                    guard offset >= 0, offset > previous else { throw PatternError.invalid("AHAPの変化点は時刻順にしてください。") }
                    previous = offset
                    end = max(end, time + offset)
                }
            } else { throw PatternError.invalid("AHAPのPattern要素を読み込めません。") }
        }
        guard (1...256).contains(events), end <= 30 else {
            throw PatternError.invalid("サンプルのAHAPは30秒・256イベント以内にしてください。")
        }
        dictionary = root; duration = max(0.1, end); containsAudio = audio
    }

    func pattern() throws -> CHHapticPattern {
        try CHHapticPattern(dictionary: Dictionary(uniqueKeysWithValues: dictionary.map {
            (CHHapticPattern.Key(rawValue: $0.key), $0.value)
        }))
    }

    static func encode(_ source: HapticPatternSpec) throws -> Data {
        let source = try source.validated()
        var entries: [[String: Any]] = source.events.map { event in
            var value: [String: Any] = ["Time": event.time,
                "EventType": event.kind == .tap ? "HapticTransient" : "HapticContinuous",
                "EventParameters": [["ParameterID": "HapticIntensity", "ParameterValue": event.intensity],
                                    ["ParameterID": "HapticSharpness", "ParameterValue": event.sharpness]]]
            if event.kind == .continuous { value["EventDuration"] = event.duration }
            return ["Event": value]
        }
        entries += source.dynamicParameters.map { parameter in
            ["Parameter": ["Time": parameter.time, "ParameterID": identifier(parameter.parameter),
                           "ParameterValue": parameter.value]]
        }
        entries += source.curves.map { curve in
            let start = curve.points[0].time
            return ["ParameterCurve": ["Time": start, "ParameterID": identifier(curve.parameter),
                "ParameterCurveControlPoints": curve.points.map {
                    ["Time": $0.time - start, "ParameterValue": $0.value]
                }]]
        }
        return try JSONSerialization.data(withJSONObject: ["Version": 1,
            "Metadata": ["Project": "Reson", "Description": source.name], "Pattern": entries],
            options: [.prettyPrinted, .sortedKeys])
    }

    private static func identifier(_ parameter: HapticCurveSpec.Parameter) -> String {
        parameter == .intensity ? "HapticIntensityControl" : "HapticSharpnessControl"
    }
}

struct AHAPFile: FileDocument {
    static var readableContentTypes: [UTType] { [.resonAHAP, .json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let resonAHAP = UTType(exportedAs: "com.reson.haptic-pattern", conformingTo: .json)
}
