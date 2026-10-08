import CoreHaptics
import QuartzCore

@MainActor
final class MusicHapticRenderer {
    private var engine: CHHapticEngine?
    private var players: [UUID: CHHapticAdvancedPatternPlayer] = [:]
    private var anchorEngine: Double?
    private var anchorMedia = 0.0
    private var nextEngine = 0.0
    private var nextMedia = 0.0
    private var clockGate = MusicPlaybackGate()
    private var previousRate = 1.0
    private var generation = 0
    private var watchdog: Task<Void, Never>?
    var onFailure: ((String) -> Void)?
    var settings = MusicSettings() { didSet { if oldValue != settings { stopPlayers() } } }
    let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    var isRendering: Bool { anchorEngine != nil }

    func synchronize(track: MusicHapticTrack?, position: Double, playing: Bool, rate: Double, clockPosition: Double? = nil) {
        guard supported, let track, position.isFinite, position >= 0, playing,
              rate.isFinite, (0.25...2).contains(rate) else { stop(); return }
        let host = CACurrentMediaTime()
        guard clockGate.accept(position: clockPosition ?? position, playing: playing, rate: rate, hostTime: host) else { stopPlayers(); return }
        let media = position - settings.normalized.offset
        guard media >= 0, media < track.duration else { stopPlayers(); return }
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            guard let self else { return }
            self.stopPlayers()
        }
        do {
            let engine = try readyEngine()
            let now = engine.currentTime
            if let anchorEngine {
                let predicted = anchorMedia + (now - anchorEngine) * previousRate
                if abs(predicted - media) > 0.06 || previousRate != rate { stopPlayers() }
            }
            if anchorEngine == nil {
                anchorEngine = now + 0.02
                anchorMedia = media + 0.02 * rate
                nextEngine = now + 0.02
                nextMedia = anchorMedia
                previousRate = rate
            }
            while nextEngine - now < 0.2, nextMedia < track.duration {
                let length = min(0.6 * rate, track.duration - nextMedia)
                for specification in track.segment(at: nextMedia, length: length, rate: rate, settings: settings) {
                    try schedule(specification, at: nextEngine, engine: engine)
                }
                nextMedia += length
                nextEngine += length / rate
            }
        } catch {
            stop()
            onFailure?("振動が中断されました。\(error.localizedDescription)")
        }
    }

    func stop() {
        stopPlayers()
        watchdog?.cancel()
        watchdog = nil
        clockGate.reset()
    }

    func suspend() {
        stop()
        let previous = engine
        engine = nil
        previous?.stop(completionHandler: nil)
    }

    private func stopPlayers() {
        generation += 1
        let previous = players
        players = [:]
        anchorEngine = nil
        for player in previous.values { try? player.stop(atTime: CHHapticTimeImmediate) }
    }

    private func readyEngine() throws -> CHHapticEngine {
        if let engine { try engine.start(); return engine }
        let new = try CHHapticEngine()
        new.playsHapticsOnly = true
        new.isAutoShutdownEnabled = true
        new.stoppedHandler = { [weak self, weak new] reason in
            Task { @MainActor [weak self, weak new] in
                guard let self, let new, self.engine === new, reason != .idleTimeout else { return }
                self.stop()
                self.onFailure?("振動が中断されました。再生ボタンで再開できます。")
            }
        }
        new.resetHandler = { [weak self, weak new] in
            Task { @MainActor [weak self, weak new] in
                guard let self, let new, self.engine === new else { return }
                self.stop()
                self.engine = nil
                self.onFailure?("振動が中断されました。再生ボタンで再開できます。")
            }
        }
        engine = new
        try new.start()
        return new
    }

    static func makePattern(_ specification: HapticPatternSpec) throws -> CHHapticPattern {
        let specification = try specification.validated()
        if !specification.dynamicParameters.isEmpty {
            // Core Haptics exposes separate event/parameter and event/curve initializers.
            // The AHAP dictionary initializer preserves both in the same pattern.
            return try HapticAHAP(data: HapticAHAP.encode(specification)).pattern()
        }
        let events = specification.events.map {
            CHHapticEvent(eventType: $0.kind == .tap ? .hapticTransient : .hapticContinuous, parameters: [
                .init(parameterID: .hapticIntensity, value: Float($0.intensity)),
                .init(parameterID: .hapticSharpness, value: Float($0.sharpness))
            ], relativeTime: $0.time, duration: $0.duration)
        }
        let curves = specification.curves.map { curve in
            let start = curve.points[0].time
            return CHHapticParameterCurve(parameterID: curve.parameter == .intensity ? .hapticIntensityControl : .hapticSharpnessControl,
                controlPoints: curve.points.map { .init(relativeTime: $0.time - start, value: Float($0.value)) }, relativeTime: start)
        }
        return try CHHapticPattern(events: events, parameterCurves: curves)
    }

    private func schedule(_ specification: HapticPatternSpec, at time: Double, engine: CHHapticEngine) throws {
        let player = try engine.makeAdvancedPlayer(with: Self.makePattern(specification))
        let id = UUID(), token = generation
        player.completionHandler = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, token == self.generation else { return }
                self.players[id] = nil
                if let error { self.stop(); self.onFailure?(error.localizedDescription) }
            }
        }
        players[id] = player
        try player.start(atTime: time)
    }
}

