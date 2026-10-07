import SwiftUI

struct HapticSpectrumSnapshot {
    let audio: [Double]
    let haptics: [Double]
    let output: MusicHapticOutput
}

enum HapticVisualSignal {
    static func level(track: MusicHapticTrack, time: Double, settings: MusicSettings) -> Double {
        track.output(at: time - settings.normalized.offset, settings: settings).level
    }

    static func timeline(track: MusicHapticTrack, settings: MusicSettings, position: Double, count: Int, span: Double = 4) -> [Double] {
        guard count > 1, position.isFinite, span.isFinite, span > 0 else { return [] }
        return (0..<count).map { index in
            level(track: track, time: position - span / 2 + Double(index) / Double(count - 1) * span, settings: settings)
        }
    }

    static func spectrum(track: MusicHapticTrack, time: Double, settings: MusicSettings, active: Bool) -> HapticSpectrumSnapshot? {
        guard time.isFinite, let audio = track.spectrum(at: time) else { return nil }
        let settings = settings.normalized
        let sourceTime = time - settings.offset
        let output = active ? track.output(at: sourceTime, settings: settings) : MusicHapticOutput(continuous: 0, sharpness: 0, transient: 0)
        if track.version == 3 {
            // An arranged instrument has no one-to-one frequency attribution to the audio.
            return .init(audio: audio, haptics: Array(repeating: 0, count: audio.count), output: output)
        }
        let source = track.spectrum(at: sourceTime) ?? audio
        let precision = track.value(at: sourceTime).texture != nil
        let firstTap = lowerBound(track.taps, time: max(0, sourceTime - 0.06), key: { $0.time })
        let lastTap = lowerBound(track.taps, time: max(0, sourceTime + 0.000_000_1), key: { $0.time })
        let tap = track.taps[firstTap..<lastTap].filter { settings.includes($0) }.max { left, right in
            func level(_ value: MusicTap) -> Double {
                settings.intensity(for: value) * max(0, 1 - (sourceTime - value.time) / 0.06)
            }
            return level(left) < level(right)
        }
        let weighted = source.enumerated().map { index, level -> Double in
            let frequency = MusicFrequencyBands.centers[index]
            if precision {
                let bassWeight = (30..<70).contains(frequency) ? 0.70
                    : (70..<140).contains(frequency) ? 0.55 : (140..<300).contains(frequency) ? 0.25 : 0
                let tapWeight: Double
                if let tap {
                    // Frequency attribution follows the analyzed sound, not the user's touch sharpness.
                    tapWeight = tap.sharpness < 0.35 ? ((30..<300).contains(frequency) ? 1 : 0)
                        : tap.sharpness < 0.75 ? ((300..<2_000).contains(frequency) ? 1 : 0)
                        : ((2_000...8_000).contains(frequency) ? 1 : 0)
                } else { tapWeight = 0 }
                switch settings.mode {
                case .bass: return level * bassWeight * settings.bass
                case .mix: return level * ((bassWeight * settings.bass * 0.65 + 0.08) * settings.continuousGain + tapWeight * output.transient)
                case .beats: return level * tapWeight
                case .energy: return level
                }
            }
            switch settings.mode {
            case .bass: return frequency < 120 ? level * settings.bass : 0
            case .mix:
                let weight = frequency < 120 ? settings.bass * 0.65 : (frequency < 500 ? 0.20 : 0)
                return level * ((weight + 0.08) * settings.continuousGain + output.transient)
            case .energy, .beats: return level
            }
        }
        let peak = weighted.max() ?? 0
        let haptics = weighted.map { peak > 0 ? $0 / peak * output.level : 0 }
        return .init(audio: audio, haptics: haptics, output: output)
    }
}

struct HapticTimelineView: View {
    let track: MusicHapticTrack?
    let position: Double
    let settings: MusicSettings
    var compact = false
    var playing = false

    var body: some View {
        let levels = track.map { HapticVisualSignal.timeline(track: $0, settings: settings, position: position, count: compact ? 101 : 201) } ?? []
        return Canvas { context, size in
            guard let track, levels.count > 1 else { return }
            let span = 4.0, start = position - span / 2
            let width = size.width / Double(levels.count)
            for (index, level) in levels.enumerated() {
                let height = max(1, level * (size.height - 8))
                let rect = CGRect(x: Double(index) * width, y: size.height - 4 - height, width: max(1, width - 0.5), height: height)
                let color = index <= levels.count / 2 ? LabTheme.mint : LabTheme.muted.opacity(0.35)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
            let normalized = settings.normalized
            let first = lowerBound(track.taps, time: start - normalized.offset, key: { $0.time })
            let last = lowerBound(track.taps, time: start + span - normalized.offset, key: { $0.time })
            for tap in track.taps[first..<last] where normalized.includes(tap) {
                let x = (tap.time + normalized.offset - start) / span * size.width
                let height = normalized.intensity(for: tap) * (size.height - 8)
                var pulse = Path()
                pulse.move(to: CGPoint(x: x, y: size.height - 4))
                pulse.addLine(to: CGPoint(x: x, y: size.height - 4 - height))
                context.stroke(pulse, with: .color(.white.opacity(0.8)), lineWidth: 2)
            }
            var marker = Path()
            marker.move(to: CGPoint(x: size.width / 2, y: 0))
            marker.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            context.stroke(marker, with: .color(.white.opacity(playing ? 0.9 : 0.45)), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("現在の前後2秒の振動")
        .accessibilityValue(musicTime(position) + "、\(levels.filter { $0 > 0 }.count)区間の振動")
        .accessibilityIdentifier("haptics.waveform")
    }
}

struct HapticSpectrumView: View {
    let track: MusicHapticTrack?
    let position: Double
    let settings: MusicSettings
    var active = false
    var compact = false

    var body: some View {
        let snapshot = track.flatMap { HapticVisualSignal.spectrum(track: $0, time: position, settings: settings, active: active) }
        return VStack(spacing: 4) {
            if let snapshot {
                Canvas { context, size in
                    let width = size.width / Double(MusicFrequencyBands.count)
                    for index in 0..<MusicFrequencyBands.count {
                        for (level, color) in [(snapshot.audio[index], LabTheme.muted.opacity(0.35)), (snapshot.haptics[index], LabTheme.mint)] {
                            guard level > 0 else { continue }
                            let height = level * size.height
                            let rect = CGRect(x: Double(index) * width, y: size.height - height, width: max(1, width - 3), height: height)
                            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(track?.version == 3 ? "音の周波数（参考）" : "音の周波数と振動への反映")
                .accessibilityValue("\(MusicFrequencyBands.count)帯域、振動\(Int(snapshot.output.level * 100))パーセント")
                .accessibilityIdentifier("haptics.spectrum")
                if !compact {
                    HStack {
                        Text("20 Hz")
                        Spacer()
                        Text("振動 \(Int(snapshot.output.level * 100))%").foregroundStyle(LabTheme.mint)
                        Spacer()
                        Text("8 kHz")
                    }.font(.system(size: 9, design: .monospaced)).foregroundStyle(LabTheme.muted)
                }
            } else {
                Text(track == nil ? "振動を作成すると周波数を表示します" : "周波数表示には、この曲の振動を作り直してください")
                    .font(.system(size: compact ? 9 : 11)).foregroundStyle(LabTheme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("haptics.needsSpectrum")
            }
        }
    }
}

struct MusicArtwork: View {
    let selection: MusicSelection?
    var compact = false
    var body: some View {
        Group {
            if let id = selection?.videoID, let url = URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg") {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { fallback }
            } else { fallback }
        }.clipped().clipShape(RoundedRectangle(cornerRadius: compact ? 4 : 12))
    }
    private var fallback: some View {
        ZStack {
            LinearGradient(colors: [LabTheme.elevated, LabTheme.panel], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "waveform").font(.system(size: compact ? 20 : 70, weight: .light)).foregroundStyle(LabTheme.mint)
        }
    }
}
