import SwiftUI

struct ExperimentView: View {
    @EnvironmentObject private var haptics: HapticController
    @AppStorage("experiment.kind") private var kindRaw = HapticKind.continuous.rawValue
    @AppStorage("experiment.intensity") private var intensity = 0.65
    @AppStorage("experiment.sharpness") private var sharpness = 0.5
    @AppStorage("experiment.duration") private var duration = 1.5
    @AppStorage("experiment.interval") private var interval = 0.2
    @AppStorage("experiment.bpm") private var bpm = 100.0

    private var kind: HapticKind { HapticKind(rawValue: kindRaw) ?? .continuous }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionIntro(eyebrow: "MAKE YOUR OWN", title: "触感を、調合する。",
                         detail: "強さと鋭さを変えるだけで、感触は驚くほど変わる。")

            VStack(spacing: 19) {
                HStack(spacing: 6) {
                    ForEach(HapticKind.allCases, id: \.rawValue) { item in
                        Button { kindRaw = item.rawValue; haptics.stop() } label: {
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(kind == item ? LabTheme.background : LabTheme.muted)
                                .background(kind == item ? LabTheme.mint : LabTheme.elevated,
                                            in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("kind.\(item.rawValue)")
                        .accessibilityAddTraits(kind == item ? .isSelected : [])
                    }
                }
                TactileWave(intensity: intensity, sharpness: sharpness)
                    .frame(height: 58)
                ParameterSlider(title: "強さ", valueLabel: "\(Int(intensity * 100))%",
                                leading: "かすか", trailing: "強い", identifier: "control.intensity",
                                value: $intensity, range: 0...1)
                divider
                ParameterSlider(title: "鋭さ", valueLabel: "\(Int(sharpness * 100))%",
                                leading: "やわらかい", trailing: "くっきり", identifier: "control.sharpness",
                                value: $sharpness, range: 0...1)
                if kind != .tap {
                    divider
                    ParameterSlider(title: "長さ", valueLabel: String(format: "%.1f 秒", duration),
                                    leading: "0.1 秒", trailing: "5.0 秒", identifier: "control.duration",
                                    value: $duration, range: 0.1...5, step: 0.1)
                }
                if kind == .pulses {
                    divider
                    ParameterSlider(title: "連打の間隔", valueLabel: "\(Int(interval * 1_000)) ms",
                                    leading: "速い", trailing: "ゆっくり", identifier: "control.interval",
                                    value: $interval, range: 0.08...0.8, step: 0.01)
                }
                PrimaryButton(title: "この触感を再生") {
                    haptics.play(PatternFactory.experiment(ExperimentConfiguration(
                        kind: kind, intensity: intensity, sharpness: sharpness,
                        duration: duration, interval: interval
                    )))
                }
                .accessibilityIdentifier("experiment.play")
                Text("設定は自動で保存されます。変更後は再生ボタンを押してください。")
                    .font(.system(size: 10)).foregroundStyle(LabTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .labPanel()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "metronome").foregroundStyle(LabTheme.violet)
                    Text("リズムを刻む").font(.system(size: 16, weight: .bold))
                }
                Text("4拍ごとにアクセント。音楽と触感を合わせる、最初の実験。")
                    .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                ParameterSlider(title: "テンポ", valueLabel: "\(Int(bpm)) BPM",
                                leading: "ゆっくり", trailing: "速い", identifier: "control.bpm",
                                value: $bpm, range: 40...200, step: 1)
                PrimaryButton(title: "リズムを再生", symbol: "repeat") {
                    haptics.play(PatternFactory.metronome(bpm: bpm, intensity: intensity, sharpness: sharpness), loop: true)
                }
                .accessibilityIdentifier("rhythm.play")
                Text("下の停止ボタンで止まります。1回の再生は最大60秒。")
                    .font(.system(size: 10)).foregroundStyle(LabTheme.muted)
            }
            .labPanel()
        }
        .onAppear {
            let normalized = ExperimentConfiguration(kind: kind, intensity: intensity, sharpness: sharpness,
                                                      duration: duration, interval: interval).normalized
            intensity = normalized.intensity
            sharpness = normalized.sharpness
            duration = normalized.duration
            interval = normalized.interval
            bpm = bounded(bpm, to: 40...200, fallback: 100)
        }
    }

    private var divider: some View { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
}

