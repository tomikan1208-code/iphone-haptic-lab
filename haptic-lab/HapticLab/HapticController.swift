import CoreHaptics
import SwiftUI
import UIKit

@MainActor
final class HapticController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var activeName = "待機中"
    @Published private(set) var isPadPlaying = false
    @Published var message: String?

    let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var timeoutTask: Task<Void, Never>?
    private var generation = 0

    func play(_ specification: HapticPatternSpec, loop: Bool = false) {
        guard checkSupport() else { return }
        stop()
        do {
            let specification = try specification.validated()
            let events = specification.events.map { event in
                CHHapticEvent(
                    eventType: event.kind == .tap ? .hapticTransient : .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(event.intensity)),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(event.sharpness))
                    ],
                    relativeTime: event.time,
                    duration: event.duration
                )
            }
            let curves = specification.curves.map { curve in
                CHHapticParameterCurve(
                    parameterID: curve.parameter == .intensity ? .hapticIntensityControl : .hapticSharpnessControl,
                    controlPoints: curve.points.map {
                        CHHapticParameterCurve.ControlPoint(relativeTime: $0.time, value: Float($0.value))
                    },
                    relativeTime: 0
                )
            }
            let pattern = try CHHapticPattern(events: events, parameterCurves: curves)
            try start(pattern, name: specification.name, loopDuration: loop ? specification.duration : nil)
            // Loops are bounded sessions. A new touch/play always creates a new generation.
            scheduleStop(after: loop ? 60 : specification.duration + 0.25)
        } catch {
            fail(error)
        }
    }

    func beginPad(intensity: Double, sharpness: Double) {
        guard checkSupport() else { return }
        stop()
        do {
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0)
            ], relativeTime: 0, duration: 20)
            let parameters = padParameters(intensity: intensity, sharpness: sharpness)
            let pattern = try CHHapticPattern(events: [event], parameters: parameters)
            try start(pattern, name: "指で触感を探索", loopDuration: nil)
            isPadPlaying = true
            scheduleStop(after: 20)
        } catch {
            fail(error)
        }
    }

    func updatePad(intensity: Double, sharpness: Double) {
        guard isPadPlaying, let player else { return }
        do {
            try player.sendParameters(padParameters(intensity: intensity, sharpness: sharpness),
                                      atTime: CHHapticTimeImmediate)
        } catch {
            fail(error)
        }
    }

    func endPad() {
        if isPadPlaying { stop() }
    }

    func playSystem(_ feedback: SystemFeedback) {
        guard checkSupport() else { return }
        stop()
        switch feedback {
        case .light, .medium, .heavy, .soft, .rigid:
            let generator = UIImpactFeedbackGenerator(style: feedback.impactStyle)
            generator.prepare()
            generator.impactOccurred()
        case .selection:
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        case .success, .warning, .error:
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(feedback.notificationType)
        }
        activeName = "標準 · \(feedback.title)"
        isPlaying = true
        scheduleStop(after: 0.6)
    }

    func stop() {
        generation += 1
        timeoutTask?.cancel()
        timeoutTask = nil
        let previousPlayer = player
        player = nil
        try? previousPlayer?.stop(atTime: CHHapticTimeImmediate)
        isPlaying = false
        isPadPlaying = false
        activeName = "待機中"
    }

    func suspend() {
        stop()
        // Dropping the reference also prevents a stale engine callback from restarting playback.
        let previousEngine = engine
        engine = nil
        previousEngine?.stop(completionHandler: nil)
    }

    private func checkSupport() -> Bool {
        guard supportsHaptics else {
            message = "この環境では振動を再生できません。iPhone SE（第3世代）の実機で開いてください。"
            return false
        }
        message = nil
        return true
    }

    private func readyEngine() throws -> CHHapticEngine {
        if let engine {
            try engine.start()
            return engine
        }
        let newEngine = try CHHapticEngine()
        newEngine.playsHapticsOnly = true
        newEngine.isAutoShutdownEnabled = true
        newEngine.stoppedHandler = { [weak self, weak newEngine] reason in
            Task { @MainActor [weak self, weak newEngine] in
                guard let self, let newEngine, self.engine === newEngine else { return }
                // An idle notification can arrive after a newer start request.
                // Each play explicitly starts the engine, so this notification needs no state change.
                if reason == .idleTimeout { return }
                self.stop()
                self.message = "振動が中断されました。もう一度再生できます。"
            }
        }
        newEngine.resetHandler = { [weak self, weak newEngine] in
            Task { @MainActor [weak self, weak newEngine] in
                guard let self, let newEngine, self.engine === newEngine else { return }
                self.stop()
                self.engine = nil
                self.message = "振動が中断されました。もう一度再生できます。"
            }
        }
        engine = newEngine
        try newEngine.start()
        return newEngine
    }

    private func start(_ pattern: CHHapticPattern, name: String, loopDuration: Double?) throws {
        let engine = try readyEngine()
        let newPlayer = try engine.makeAdvancedPlayer(with: pattern)
        let token = generation
        if let loopDuration {
            newPlayer.loopEnabled = true
            newPlayer.loopEnd = loopDuration
        }
        newPlayer.completionHandler = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.stop()
                if let error { self.message = error.localizedDescription }
            }
        }
        player = newPlayer
        activeName = name
        isPlaying = true
        try newPlayer.start(atTime: CHHapticTimeImmediate)
    }

    private func padParameters(intensity: Double, sharpness: Double) -> [CHHapticDynamicParameter] {
        [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                     value: Float(bounded(intensity, to: 0...1, fallback: 0)), relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl,
                                     value: Float(bounded(sharpness, to: 0...1, fallback: 0)), relativeTime: 0)
        ]
    }

    private func scheduleStop(after seconds: Double) {
        timeoutTask?.cancel()
        let token = generation
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.stop()
            } catch { /* Cancellation belongs to a newer playback session. */ }
        }
    }

    private func fail(_ error: Error) {
        stop()
        message = "振動を再生できませんでした。\n\(error.localizedDescription)"
    }
}

enum SystemFeedback: String, CaseIterable, Identifiable {
    case light, medium, heavy, soft, rigid, selection, success, warning, error
    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "軽い"
        case .medium: return "中くらい"
        case .heavy: return "重い"
        case .soft: return "柔らかい"
        case .rigid: return "硬い"
        case .selection: return "選択"
        case .success: return "成功"
        case .warning: return "注意"
        case .error: return "エラー"
        }
    }

    var impactStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light: return .light
        case .heavy: return .heavy
        case .soft: return .soft
        case .rigid: return .rigid
        default: return .medium
        }
    }

    var notificationType: UINotificationFeedbackGenerator.FeedbackType {
        switch self {
        case .success: return .success
        case .warning: return .warning
        default: return .error
        }
    }
}
