import SwiftUI

enum HapticVisualSignal {
    static let sampleRate = 50.0
    static let sampleCount = 128

    static func timeline(track: MusicHapticTrack, settings: MusicSettings, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let settings = settings.normalized
        var bins = [Double](repeating: 0, count: count)
        func add(_ time: Double, _ intensity: Double) {
            let displayedTime = time + settings.offset
            guard displayedTime >= 0, displayedTime < track.duration else { return }
            let index = min(count - 1, Int(displayedTime / track.duration * Double(count)))
            bins[index] = max(bins[index], min(1, intensity))
        }
        for point in track.envelope { add(point.time, settings.intensity(for: point)) }
        if settings.mode == .mix || settings.mode == .beats {
            for tap in track.taps where tap.intensity >= (1 - settings.density) * 0.7 {
                add(tap.time, tap.intensity * settings.gain)
            }
        }
        return bins
    }

    static func level(track: MusicHapticTrack, time: Double, settings: MusicSettings) -> Double {
        let time = time - settings.normalized.offset
        guard time >= 0, time < track.duration else { return 0 }
        let settings = settings.normalized
        let sustained = settings.intensity(for: track.value(at: time))
        guard settings.mode == .mix || settings.mode == .beats else { return sustained }
        let first = lowerBound(track.taps, time: time - 0.06, key: { $0.time })
        let last = lowerBound(track.taps, time: time + 0.06, key: { $0.time })
        let tap = track.taps[first..<last].filter { $0.intensity >= (1 - settings.density) * 0.7 }
            .map { $0.intensity * settings.gain * max(0, 1 - abs($0.time - time) / 0.06) }.max() ?? 0
        return min(1, max(sustained, tap))
    }

    // Fourier transform of the stored strength envelope, not an estimate of the motor's carrier frequency.
    static func spectrum(_ samples: [Double]) -> [Double] {
        guard samples.count == sampleCount, samples.allSatisfy(\.isFinite) else { return [] }
        let mean = samples.reduce(0, +) / Double(sampleCount)
        let window = samples.enumerated().map { index, value in
            (value - mean) * (0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(sampleCount - 1)))
        }
        return (1...sampleCount / 2).map { bin in
            var real = 0.0, imaginary = 0.0
            for index in 0..<sampleCount {
                let phase = 2 * .pi * Double(bin * index) / Double(sampleCount)
                real += window[index] * cos(phase)
                imaginary -= window[index] * sin(phase)
            }
            return sqrt(real * real + imaginary * imaginary) * 4 / Double(sampleCount)
        }
    }
}

struct HapticTimelineView: View {
    let track: MusicHapticTrack?
    let position: Double
    let settings: MusicSettings
    var compact = false
    var playing = false
    @State private var levels: [Double] = []

    var body: some View {
        // Read cached state in body so updating it invalidates Canvas before playback starts.
        let renderedLevels = levels
        return Canvas { context, size in
            guard let track else { return }
            let count = renderedLevels.count
            guard count > 0 else { return }
            let progress = min(1, max(0, position / track.duration))
            for index in 0..<count {
                let level = renderedLevels[index]
                let height = max(2, level * (size.height - 8))
                let width = size.width / Double(count)
                let rect = CGRect(x: Double(index) * width, y: (size.height - height) / 2,
                                  width: max(1, width - 1), height: height)
                let color = Double(index) / Double(count) <= progress ? LabTheme.mint : LabTheme.muted.opacity(0.38)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
            var marker = Path()
            marker.move(to: CGPoint(x: progress * size.width, y: 1))
            marker.addLine(to: CGPoint(x: progress * size.width, y: size.height - 1))
            context.stroke(marker, with: .color(.white.opacity(playing ? 0.9 : 0.45)), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("保存した振動の波形")
        .accessibilityValue(musicTime(position) + "、\(renderedLevels.filter { $0 > 0 }.count)区間の振動")
        .accessibilityIdentifier("haptics.waveform")
        .onAppear { update() }
        .onChange(of: settings) { _ in update() }
        .onChange(of: track?.audioSHA256) { _ in update() }
        .onChange(of: track?.analysis) { _ in update() }
    }
    private func update() {
        levels = track.map { HapticVisualSignal.timeline(track: $0, settings: settings, count: compact ? 100 : 150) } ?? []
    }
}

struct HapticSpectrumView: View {
    let track: MusicHapticTrack?
    let position: Double
    let settings: MusicSettings
    var body: some View {
        Canvas { context, size in
            guard let track else { return }
            let samples = (0..<HapticVisualSignal.sampleCount).map { index in
                HapticVisualSignal.level(track: track, time: position - Double(HapticVisualSignal.sampleCount - 1 - index) / HapticVisualSignal.sampleRate, settings: settings)
            }
            let spectrum = HapticVisualSignal.spectrum(samples)
            let bands = 24
            for band in 0..<bands {
                let first = max(0, Int(pow(Double(band) / Double(bands), 1.5) * Double(spectrum.count)))
                let last = max(first + 1, Int(pow(Double(band + 1) / Double(bands), 1.5) * Double(spectrum.count)))
                let magnitude = spectrum[first..<min(last, spectrum.count)].max() ?? 0
                let height = max(1, min(1, pow(magnitude * 4, 0.65)) * size.height)
                let width = size.width / Double(bands)
                context.fill(Path(roundedRect: CGRect(x: Double(band) * width, y: size.height - height,
                    width: max(1, width - 3), height: height), cornerRadius: 2), with: .color(LabTheme.mint))
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("振動の強弱の周波数表示")
            .accessibilityIdentifier("haptics.spectrum")
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
