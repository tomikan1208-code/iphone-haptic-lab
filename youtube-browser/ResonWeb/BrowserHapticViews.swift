import SwiftUI

enum BrowserSheet: Identifiable {
    case menu, preparation(MusicSelection), adjustment(MusicSelection), progress
    var id: String {
        switch self {
        case .menu: return "menu"
        case .preparation(let selection): return "prepare-" + selection.id
        case .adjustment(let selection): return "adjust-" + selection.id
        case .progress: return "progress"
        }
    }
}

struct BrowserHapticBar: View {
    @EnvironmentObject private var haptics: BrowserHaptics
    @EnvironmentObject private var library: MusicLibrary
    @Binding var sheet: BrowserSheet?
    var body: some View {
        HStack(spacing: 12) {
            if let progress = library.preparation {
                Button { sheet = .progress } label: {
                    HStack(spacing: 12) {
                        ProgressView().tint(WebTheme.mint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("振動を作成中 · \(Int(progress.fraction * 100))%")
                            Text(progress.message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.up")
                    }
                }.accessibilityIdentifier("browser.haptics.progress")
            } else if let selection = haptics.selection {
                Button { haptics.enabled.toggle() } label: {
                    Image(systemName: haptics.enabled ? "waveform" : "waveform.slash")
                        .font(.system(size: 22)).foregroundStyle(haptics.enabled ? WebTheme.mint : .gray)
                        .frame(width: 36, height: 44)
                }.accessibilityLabel(haptics.enabled ? "振動をオフ" : "振動をオン")
                    .accessibilityIdentifier("browser.haptics.toggle").accessibilityValue(haptics.enabled ? "オン" : "オフ")
                VStack(alignment: .leading, spacing: 4) {
                    Text(haptics.status.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        .accessibilityIdentifier("browser.haptics.status")
                    Text(selection.title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--browser-haptics-fixture") {
                        Text(String(format: "%.2f", haptics.position)).font(.caption2).monospacedDigit()
                            .accessibilityIdentifier("browser.haptics.clock")
                    }
                    #endif
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(haptics.record?.isPrepared == true ? "調整" : "作成") {
                    sheet = haptics.record?.isPrepared == true ? .adjustment(selection) : .preparation(selection)
                }.font(.system(size: 13, weight: .bold)).foregroundStyle(WebTheme.mint).frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier(haptics.record?.isPrepared == true ? "browser.haptics.adjust" : "browser.haptics.prepare")
            }
        }.font(.system(size: 13, weight: .semibold)).buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.vertical, 5).background(WebTheme.panel)
            .accessibilityElement(children: .contain).accessibilityIdentifier("browser.haptics.bar")
    }
}

struct BrowserHapticSettingsView: View {
    let selection: MusicSelection
    let prepareAgain: () -> Void
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var haptics: BrowserHaptics
    @Environment(\.dismiss) private var dismiss
    @State private var deletion = false
    private var record: MusicRecord? { library.record(for: selection) }
    private var settings: Binding<MusicSettings> {
        Binding(get: { library.settings(for: selection.id) }, set: { library.saveSettings($0, id: selection.id) })
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(selection.title).font(.title3.bold())
                    Text("YouTubeの動画を再生したまま調整できます。変更は自動保存されます。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let record, !record.analysisVariants.isEmpty {
                        Picker("使用する解析", selection: Binding(get: { record.selectedVariantID ?? "" }, set: { id in
                            do { _ = try library.selectVariant(id, for: record.id) }
                            catch { library.message = error.localizedDescription }
                        })) {
                            ForEach(record.analysisVariants) { variant in Text(variant.title + " · " + variant.dateText).tag(variant.id) }
                        }.accessibilityIdentifier("browser.haptics.variant")
                    }
                    Text(record?.hasIndividualSettings == true ? "この動画の個別設定" : "グローバル設定を使用中")
                        .font(.caption).foregroundStyle(WebTheme.mint).accessibilityIdentifier("browser.haptics.settingsScope")
                    MusicVibrationSettingsEditor(settings: settings, arranged: record?.analysis?.style == .arranged,
                                                 identifierPrefix: "browser.haptics").labPanel()
                    Button("グローバル設定に戻す") { library.resetSettingsToGlobal(id: selection.id) }
                        .accessibilityIdentifier("browser.haptics.resetToGlobal")
                    Button("この調整をグローバル設定にする") {
                        library.saveGlobalSettings(settings.wrappedValue, adoptingFor: selection.id)
                    }
                    Button("振動を作り直す", action: prepareAgain).accessibilityIdentifier("browser.haptics.prepareAgain")
                    Button("削除する解析を選ぶ", role: .destructive) { deletion = true }
                    if !haptics.supported {
                        Text("この端末では振動を鳴らせません。対応するiPhoneで再生してください。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let message = library.message { MusicMessage(text: message) { library.message = nil } }
                    if let message = haptics.message { MusicMessage(text: message) { haptics.message = nil } }
                }.padding(16)
            }.background(WebTheme.background).foregroundStyle(.white)
                .navigationTitle("振動を調整").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }.accessibilityIdentifier("browser.haptics.closeSettings")
                } }
                .sheet(isPresented: $deletion) { NavigationStack { MusicAnalysisDeletionView(recordID: selection.id) } }
        }.tint(WebTheme.mint)
    }
}

struct BrowserSavedHapticsView: View {
    let close: () -> Void
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var browser: YouTubeBrowser
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            if library.prepared.isEmpty {
                Text("動画を開いて「作成」を押すと、保存した振動がここに表示されます。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(library.prepared) { record in
                Button { browser.openVideo(record.selection); close() } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.selection.title).foregroundStyle(.white)
                        Text("\(record.analysisVariants.count)件の解析 · YouTubeで開く")
                            .font(.caption).foregroundStyle(WebTheme.mint)
                    }.padding(.vertical, 6)
                }.accessibilityIdentifier("browser.saved.\(record.selection.videoID ?? record.id)")
            }
        }.scrollContentBackground(.hidden).background(WebTheme.background)
            .navigationTitle("保存した振動").navigationBarTitleDisplayMode(.inline)
    }
}

struct BrowserPreparationProgressView: View {
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let progress = library.preparation {
                    Text("振動を作成中").font(.title2.bold())
                    Text(progress.selection.title).font(.headline)
                    ProgressView(value: progress.fraction).tint(WebTheme.mint)
                    Text(progress.message).font(.subheadline)
                    Text("作成中はアプリを開いたままにしてください。動画の再生はYouTube側で操作できます。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("キャンセル", role: .destructive) { library.cancelPreparation(); dismiss() }
                } else {
                    Text(library.message ?? "振動を保存しました").font(.headline)
                    Button("閉じる") { dismiss() }
                }
                Spacer()
            }.padding(24).background(WebTheme.background).foregroundStyle(.white)
                .navigationTitle("振動を作成").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("動画に戻る") { dismiss() } } }
        }
    }
}
