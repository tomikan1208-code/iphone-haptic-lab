import Foundation

enum MusicComposer {
    static func orchestral(_ source: MusicHapticTrack) throws -> MusicHapticTrack {
        var bass = 0.0, energy = 0.0
        let envelope = source.envelope.map { point -> MusicEnvelopePoint in
            bass += (point.bass - bass) * (point.bass > bass ? 0.15 : 0.06)
            energy += (point.energy - energy) * (point.energy > energy ? 0.15 : 0.06)
            if point.energy == 0 { bass = 0; energy = 0 }
            return .init(time: point.time, bass: bass * 0.75, energy: energy * 0.6, sharpness: point.sharpness * 0.4,
                         mid: point.mid.map { $0 * 0.6 }, high: point.high.map { $0 * 0.4 })
        }
        var taps: [MusicTap] = []
        for tap in source.taps where tap.intensity > 0.65 {
            if tap.time - (taps.last?.time ?? -1) >= 0.75 {
                taps.append(.init(time: tap.time, intensity: tap.intensity * 0.40, sharpness: min(0.35, tap.sharpness)))
            }
        }
        var track = MusicHapticTrack(version: source.version, audioSHA256: source.audioSHA256, duration: source.duration, envelope: envelope, taps: taps)
        track.analysis = source.analysis
        track.spectrum = source.spectrum
        track.analysis?.profile = .orchestral
        return try track.validated()
    }
    static func tempo(_ taps: [MusicTap]) -> Double {
        let taps = Array(taps.prefix(1_000))
        guard taps.count > 3 else { return 120 }
        var scores = [Double](repeating: 0, count: 121)
        for index in 1..<taps.count {
            for previous in max(0, index - 4)..<index {
                var interval = taps[index].time - taps[previous].time
                guard interval > 0 else { continue }
                while interval < 1.0 / 3 { interval *= 2 }
                while interval > 1 { interval /= 2 }
                let bpm = Int((60 / interval).rounded())
                if (60...180).contains(bpm) { scores[bpm - 60] += taps[index].intensity / Double(index - previous) }
            }
        }
        var best = 60
        var bestScore = -1.0
        for index in scores.indices {
            var score = 0.0
            for neighbor in max(0, index - 1)...min(scores.count - 1, index + 1) { score += scores[neighbor] }
            if score > bestScore { bestScore = score; best = index }
        }
        return Double(best + 60)
    }

    static func compose(_ source: MusicHapticTrack) throws -> MusicHapticTrack {
        let bpm = tempo(source.taps), interval = 60 / bpm
        let anchor = source.taps.first?.time ?? 0
        let envelope = source.envelope.map { point in
            MusicEnvelopePoint(time: point.time, bass: point.bass * 0.45,
                               energy: point.energy * 0.35, sharpness: point.sharpness * 0.6,
                               mid: point.mid.map { $0 * 0.35 }, high: point.high.map { $0 * 0.6 })
        }
        var taps: [MusicTap] = []
        var time = anchor, beat = 0
        while time < source.duration {
            try Task.checkCancellation()
            let level = source.value(at: time).energy
            let accent = beat % 4 == 0 ? 0.80 : (beat % 2 == 0 ? 0.58 : 0.40)
            if level > 0.03 {
                taps.append(.init(time: time, intensity: accent * sqrt(level), sharpness: beat % 4 == 0 ? 0.55 : 0.35))
                let offbeat = time + interval / 2
                if level > 0.72, beat % 4 < 3, offbeat < source.duration, interval / 2 >= 0.1,
                   source.value(at: offbeat).energy > 0.03 {
                    taps.append(.init(time: offbeat, intensity: 0.28 * level, sharpness: 0.45))
                }
            }
            time += interval
            beat += 1
        }
        var track = MusicHapticTrack(version: source.version, audioSHA256: source.audioSHA256,
                                     duration: source.duration, envelope: envelope, taps: taps)
        track.analysis = source.analysis
        track.spectrum = source.spectrum
        track.analysis?.style = .musical
        track.analysis?.tempoBPM = bpm
        return try track.validated()
    }
}
