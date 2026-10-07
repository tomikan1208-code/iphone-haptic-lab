import CoreHaptics
import SwiftUI
import UIKit

@MainActor
final class HapticController: ObservableObject {
    struct Layer: Identifiable {
        let id: UUID
        let name: String
        var gain: Double = 1
        var sharpness: Double = 0
    }
    @Published private(set) var isPlaying = false
    @Published private(set) var activeName = "待機中"
    @Published private(set) var isPadPlaying = false
    @Published var message: String?
    @Published private(set) var layers: [Layer] = []

    let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private var engine: CHHapticEngine?
    private var padLayerID: UUID?
    private var players: [UUID: CHHapticAdvancedPatternPlayer] = [:]
    private var layerTimeouts: [UUID: Task<Void, Never>] = [:]
    private var timeoutTask: Task<Void, Never>?
    private var generation = 0

    func play(_ specification: HapticPatternSpec, loop: Bool = false) {
        guard checkSupport() else { return }
        stop()
        do {
            let specification = try specification.validated()
            let pattern = try MusicHapticRenderer.makePattern(specification)
            try start(pattern, name: specification.name, loopDuration: loop ? specification.duration : nil)
        } catch {
            fail(error)
        }
    }

    func addLayer(_ specification: HapticPatternSpec, loop: Bool = false) {
        guard checkSupport() else { return }
        guard layers.count < 4 else { message = "レイヤーは4つまでです。使わないレイヤーを停止してください。"; return }
        do {
            let source = try specification.validated()
            _ = try start(MusicHapticRenderer.makePattern(source), name: source.name,
                          loopDuration: loop ? source.duration : nil)
        } catch { message = "レイヤーを再生できませんでした。\(error.localizedDescription)" }
    }

    func playAHAP(_ document: HapticAHAP, name: String) {
        guard checkSupport() else { return }
        stop()
        do {
            let pattern = try document.pattern()
            _ = try start(pattern, name: name, loopDuration: nil, audio: document.containsAudio)
        } catch { fail(error) }
    }

    func addAHAPLayer(_ document: HapticAHAP, name: String) {
        guard checkSupport() else { return }
        guard layers.count < 4 else { message = "レイヤーは4つまでです。"; return }
        do { _ = try start(document.pattern(), name: name, loopDuration: nil, audio: document.containsAudio) }
        catch { message = error.localizedDescription }
    }

    func updateLayer(_ id: UUID, gain: Double, sharpness: Double) {
        guard let player = players[id], let index = layers.firstIndex(where: { $0.id == id }) else { return }
        let gain = bounded(gain, to: 0...1, fallback: 0)
        let sharpness = bounded(sharpness, to: -1...1, fallback: 0)
        do {
            try player.sendParameters([
                .init(parameterID: .hapticIntensityControl, value: Float(gain), relativeTime: 0),
                .init(parameterID: .hapticSharpnessControl, value: Float(sharpness), relativeTime: 0)
            ], atTime: CHHapticTimeImmediate)
            layers[index].gain = gain; layers[index].sharpness = sharpness
        } catch { message = error.localizedDescription }
    }

    func stopLayer(_ id: UUID) {
        layerTimeouts.removeValue(forKey: id)?.cancel()
        let removed = players.removeValue(forKey: id)
        layers.removeAll { $0.id == id }
        if padLayerID == id { padLayerID = nil; isPadPlaying = false }
        try? removed?.stop(atTime: CHHapticTimeImmediate)
        if players.isEmpty { isPlaying = false; isPadPlaying = false; activeName = "待機中" }
        else { activeName = layers.map(\.name).joined(separator: " + ") }
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
            padLayerID = try start(pattern, name: "指で触感を探索", loopDuration: nil)
            isPadPlaying = true
        } catch {
            fail(error)
        }
    }

    func updatePad(intensity: Double, sharpness: Double) {
        guard isPadPlaying, let id = padLayerID, let player = players[id] else { return }
        do {
            try player.sendParameters(padParameters(intensity: intensity, sharpness: sharpness),
                                      atTime: CHHapticTimeImmediate)
        } catch {
            fail(error)
        }
    }

    func endPad() {
        if let id = padLayerID { stopLayer(id) }
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
        padLayerID = nil
        let previousPlayers = players
        players = [:]; layers = []
        for task in layerTimeouts.values { task.cancel() }
        layerTimeouts = [:]
        for item in previousPlayers.values { try? item.stop(atTime: CHHapticTimeImmediate) }
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
        newEngine.playsHapticsOnly = false
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

    @discardableResult
    private func start(_ pattern: CHHapticPattern, name: String, loopDuration: Double?, audio: Bool = false) throws -> UUID {
        if audio, !CHHapticEngine.capabilitiesForHardware().supportsAudio {
            throw PatternError.invalid("この端末はAHAPの音声を再生できません。")
        }
        let engine = try readyEngine()
        let newPlayer = try engine.makeAdvancedPlayer(with: pattern)
        timeoutTask?.cancel()
        timeoutTask = nil
        let token = generation, id = UUID()
        if let loopDuration {
            newPlayer.loopEnabled = true
            newPlayer.loopEnd = loopDuration
        }
        newPlayer.completionHandler = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token, self.players[id] != nil else { return }
                self.stopLayer(id)
                if let error { self.message = error.localizedDescription }
            }
        }
        players[id] = newPlayer
        layers.append(Layer(id: id, name: name))
        activeName = layers.map(\.name).joined(separator: " + ")
        isPlaying = true
        do { try newPlayer.start(atTime: engine.currentTime + 0.02) }
        catch { stopLayer(id); throw error }
        layerTimeouts[id] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64((loopDuration == nil ? pattern.duration + 0.25 : 60) * 1_000_000_000))
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.stopLayer(id)
            } catch { }
        }
        return id
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
