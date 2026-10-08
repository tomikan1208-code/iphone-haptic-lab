import SwiftUI
import UniformTypeIdentifiers

struct MusicPreparationView: View {
    let selection: MusicSelection
    let initialAudio: URL?
    let preview: () -> Void
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var preferences: AnalysisPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var method: MusicAnalysisMethod = .pc
    @State private var style: MusicGenerationStyle = .arranged
    @State private var profile: MusicArrangement = .standard
    @State private var quality: MusicAnalysisQuality = .precision
    @State private var selectedAudio: URL?
    @State private var initialized = false
    @State private var audioURLText = ""
    @State private var showPCSettings = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("この曲の振動を作成しますか？").font(.system(size: 22, weight: .bold))
                        .accessibilityIdentifier("music.firstPreparation")
                    Text(selection.title).font(.system(size: 17, weight: .semibold))
                    Text(selection.artist).font(.system(size: 13)).foregroundStyle(LabTheme.muted)
                    if library.record(for: selection)?.isPrepared == true {
                        Text("保存済みの解析は残し、新しい解析結果を追加します。完成後は「振動を調整」で切り替えられます。")
                            .font(.system(size: 13)).foregroundStyle(LabTheme.mint)
                    }
                    Picker("解析方法", selection: $method) {
                        ForEach(MusicAnalysisMethod.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("analysis.method")
                    Label(method == .pc ? "PCでAI解析・振動を編曲" : "iPhoneで精密解析（帯域別）",
                          systemImage: method == .pc ? "desktopcomputer" : "iphone")
                        .font(.system(size: 15, weight: .semibold))
                    if method == .device {
                        Text(MusicAnalysisQuality.precision.detail).font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                        Picker("振動の作り方", selection: $style) {
                            Text(MusicGenerationStyle.following.title).tag(MusicGenerationStyle.following)
                            Text(MusicGenerationStyle.musical.title).tag(MusicGenerationStyle.musical)
                        }.pickerStyle(.segmented).accessibilityIdentifier("analysis.style")
                    }
                    Text(style.detail).font(.system(size: 13)).foregroundStyle(LabTheme.muted)
                    Picker("仕上げ", selection: $profile) {
                        ForEach(MusicArrangement.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("analysis.profile")
                    if profile == .orchestral {
                        Text("拍ごとのタップを控え、低音・クレッシェンド・余韻をなめらかな持続振動にします。")
                            .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                    }
                    Text(method == .pc
                         ? "PCが音源を取得し、楽器・サビ・曲の雰囲気を解析して振動を編曲します。作成・作り直しは保存済みの結果を使わず、毎回解析します。振動はPCとiPhoneへ保存し、次回の再生にはPCは不要です。"
                         : "iPhoneが音源を取得し、低音・音量・打音を帯域別に精密解析します。PCは不要です。振動を保存して、次回は解析せずに再生できます。")
                        .font(.system(size: 14)).foregroundStyle(LabTheme.muted).lineSpacing(5)
                    if method == .pc {
                        Button("PCの接続設定") { showPCSettings = true }.foregroundStyle(LabTheme.mint)
                            .accessibilityIdentifier("analysis.pcSettings")
                    }
                    if let selectedAudio {
                        Text("選択した音源: \(selectedAudio.lastPathComponent)").font(.system(size: 12))
                    }
                    if selection.kind == .youtube {
                        DisclosureGroup("同じ音源のファイル・URLを使う") {
                            TextField("音声のダウンロードURL（任意）", text: $audioURLText)
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .padding(12).background(LabTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityIdentifier("analysis.audioURL")
                            Button("音源ファイルを選ぶ") { importing = true }.padding(.vertical, 8)
                        }.font(.system(size: 13)).tint(LabTheme.mint)
                    }
                    if let errorText { Text(errorText).font(.system(size: 12)).foregroundStyle(LabTheme.coral) }
                    Text("1曲20分・512 MBまで。解析中はアプリを開いたままにしてください。")
                        .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                    PrimaryButton(title: selection.kind == .youtube ? "音声を取得して振動を作成" : "解析して振動を作成", symbol: "waveform") { start() }
                    .disabled(library.preparation != nil).accessibilityIdentifier("music.prepare")
                    if selection.kind != .file {
                        Button("今は映像・音声だけ再生する") { preview() }
                            .font(.system(size: 14)).foregroundStyle(LabTheme.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .accessibilityIdentifier("music.previewOnly")
                    }
                }.padding(24)
            }
            .background(LabTheme.background).foregroundStyle(.white)
            .navigationTitle("解析方法の確認").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !initialized else { return }
            method = preferences.method
            style = method == .pc ? .arranged : (preferences.style == .musical ? .musical : .following)
            profile = preferences.profile
            quality = .precision
            initialized = true
        }
        .onChange(of: method) { method in
            style = method == .pc ? .arranged : (preferences.style == .musical ? .musical : .following)
        }
        .sheet(isPresented: $showPCSettings) {
            NavigationStack {
                AnalysisSettingsView().toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("完了") { showPCSettings = false } }
                }
            }.preferredColorScheme(.dark)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                selectedAudio = url
                errorText = nil
            } catch { errorText = error.localizedDescription }
        }
    }
    private func start() {
        errorText = nil
        preferences.method = method
        preferences.style = style
        preferences.profile = profile
        preferences.quality = quality
        if method == .pc, preferences.connection == nil { showPCSettings = true; return }
        do {
            let audioURL = audioURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : try MusicSelection.audioDownloadURL(audioURLText)
            let audioFile = selectedAudio ?? initialAudio
            if selection.kind == .file && audioFile == nil {
                importing = true
                return
            }
            library.prepare(selection, audioFile: audioFile, audioDownloadURL: audioURL,
                            method: method, style: style, profile: profile, quality: quality, connection: preferences.connection)
            if library.preparation?.selection.id == selection.id { dismiss() }
            else { errorText = library.message }
        } catch { errorText = error.localizedDescription }
    }
}

