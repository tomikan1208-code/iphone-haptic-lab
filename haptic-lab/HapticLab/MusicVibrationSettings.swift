import SwiftUI

struct MusicVibrationSettingsEditor: View {
    @Binding var settings: MusicSettings
    var arranged = false
    var identifierPrefix = "music"
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            Text("触感を調整").font(.system(size: 17, weight: .semibold))
            Button { settings.emphasizeTaps() } label: {
                Label("打音をくっきり", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(LabTheme.mint)
            }.accessibilityIdentifier("\(identifierPrefix).crispPreset")
            ParameterSlider(title: "全体の強さ", valueLabel: "\(Int((settings.gain * 100).rounded()))%", leading: "オフ", trailing: "最大400%",
                            identifier: "\(identifierPrefix).gain.settings", value: $settings.gain, range: MusicSettings.gainRange, step: 0.05)
            ParameterSlider(title: "持続振動", valueLabel: "\(Int((settings.continuousGain * 100).rounded()))%", leading: "オフ", trailing: "100%",
                            identifier: "\(identifierPrefix).continuous", value: $settings.continuousGain, range: 0...1)
            ParameterSlider(title: "瞬間振動", valueLabel: "\(Int((settings.transientGain * 100).rounded()))%", leading: "オフ", trailing: "100%",
                            identifier: "\(identifierPrefix).transient", value: $settings.transientGain, range: 0...1)
            ParameterSlider(title: "瞬間の鋭さ", valueLabel: "\(Int((settings.transientSharpness * 100).rounded()))%", leading: "柔らかく", trailing: "鋭く",
                            identifier: "\(identifierPrefix).transientSharpness", value: $settings.transientSharpness, range: 0...1)
            ParameterSlider(title: "ビートの密度", valueLabel: "\(Int(settings.density * 100))%",
                            leading: arranged ? "主要なアクセント" : "大きな打音だけ", trailing: "細かな打音も",
                            identifier: "\(identifierPrefix).density", value: $settings.density, range: 0...1)
            Text("持続と瞬間は別々に調整できます。瞬間の鋭さは50%で元の触感を保ち、上げるほど硬く、下げるほど柔らかくなります。再解析は不要です。")
                .font(.system(size: 12)).foregroundStyle(LabTheme.muted).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup(arranged ? "演奏する役割・同期" : "低音・同期の詳細") {
                VStack(alignment: .leading, spacing: 23) {
                    Picker("振動モード", selection: Binding(get: { arranged && settings.mode == .energy ? .bass : settings.mode }, set: { settings.mode = $0 })) {
                        ForEach(availableModes, id: \.self) { mode in
                            Text(modeTitle(mode)).tag(mode)
                        }
                    }.pickerStyle(.segmented).accessibilityIdentifier("\(identifierPrefix).mode")
                    if !arranged {
                        ParameterSlider(title: "低音の量", valueLabel: "\(Int(settings.bass * 100))%", leading: "控えめ", trailing: "たっぷり",
                                        identifier: "\(identifierPrefix).bass", value: $settings.bass, range: 0...1)
                    }
                    ParameterSlider(title: "同期の補正", valueLabel: String(format: "%+.0f ms", settings.offset * 1_000), leading: "振動を早く", trailing: "振動を遅く",
                                    identifier: "\(identifierPrefix).offset", value: $settings.offset, range: -1...1, step: 0.01)
                    Text("Bluetoothで音が遅れる場合は、振動を遅くする方向へ調整してください。")
                        .font(.system(size: 12)).foregroundStyle(LabTheme.muted).fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 16)
            }.tint(LabTheme.mint).accessibilityIdentifier("\(identifierPrefix).advancedSettings")
            Text("全体の強さを100%より上げると増幅し、実際の振動出力は端末の最大値までです。")
                .font(.system(size: 12)).foregroundStyle(LabTheme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var availableModes: [MusicSettings.Mode] {
        arranged ? [.mix, .beats, .bass] : MusicSettings.Mode.allCases
    }

    private func modeTitle(_ mode: MusicSettings.Mode) -> String {
        guard arranged else { return mode.title }
        switch mode {
        case .mix: return "編曲"
        case .beats: return "アクセント"
        case .bass, .energy: return "持続"
        }
    }
}

struct GlobalMusicSettingsView: View {
    @EnvironmentObject private var library: MusicLibrary

    private var settingsBinding: Binding<MusicSettings> {
        Binding(get: { library.globalSettings }, set: { library.saveGlobalSettings($0) })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("全曲の共通設定です。個別に調整していない曲と「グローバルに戻す」を選んだ曲に反映します。変更は自動保存されます。")
                    .font(.system(size: 13)).foregroundStyle(LabTheme.muted)
                MusicVibrationSettingsEditor(settings: settingsBinding, identifierPrefix: "global").labPanel()
                Button("標準値に戻す") { library.saveGlobalSettings(MusicSettings()) }
                    .foregroundStyle(LabTheme.mint).accessibilityIdentifier("global.resetDefaults")
                Text("標準値：全体70%、持続100%、瞬間100%、鋭さ50%、密度70%、同期0 ms。低音の量は65%。")
                    .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                Text("低音の量はiPhone解析の持続振動に使います。AI編曲の持続振動は「持続振動」で調整してください。")
                    .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                if let message = library.message { MusicMessage(text: message) { library.message = nil } }
            }.padding(16)
        }.background(LabTheme.background).foregroundStyle(.white).tint(LabTheme.mint)
            .navigationTitle("グローバル振動設定").navigationBarTitleDisplayMode(.inline)
    }
}
