import AVKit
import SwiftUI

struct MusicPlayerScreen: View {
    @EnvironmentObject private var playback: MusicPlayback
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var showSpectrum = true
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    mediaPlayer
                        .frame(height: min(playback.containsVideo ? 211 : 170, max(100, geometry.size.height * 0.27))).background(.black)
                        .accessibilityIdentifier("music.mediaPlayer")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            songHeader
                            if let score = playback.visualizationTrack?.arrangement { arrangementPanel(score) }
                            if let message = playback.message { MusicMessage(text: message) { playback.message = nil } }
                            if !playback.hasHaptics {
                                Text("映像・音声のみで再生します。振動を付けるには、検索や履歴からこの曲を選び、初回の作成を行ってください。")
                                    .font(.system(size: 13)).foregroundStyle(LabTheme.muted)
                            }
                        }.padding(16)
                    }
                    .scrollIndicators(.hidden)
                    VStack(spacing: 8) {
                        if playback.hasHaptics {
                            HStack {
                                Text(showSpectrum ? playback.visualizationTrack?.version == 3
                                     ? "音の周波数（参考）" : "音の周波数 · 灰：音 / 緑：振動"
                                     : "現在の前後2秒 · 白：アクセント")
                                    .font(.system(size: 10)).foregroundStyle(LabTheme.muted)
                                Spacer()
                                Button(showSpectrum ? "波形" : "周波数") { showSpectrum.toggle() }
                                    .font(.system(size: 11)).foregroundStyle(LabTheme.mint)
                                    .accessibilityIdentifier("haptics.toggle")
                            }
                            TimelineView(.animation(minimumInterval: 0.02, paused: !playback.isPlaying)) { _ in
                                Group {
                                    if showSpectrum {
                                        HapticSpectrumView(track: playback.visualizationTrack, position: playback.visualizationPosition,
                                                           settings: playback.settings, active: playback.hapticsActive)
                                    } else {
                                        HapticTimelineView(track: playback.visualizationTrack, position: playback.visualizationPosition,
                                                           settings: playback.settings, playing: playback.isPlaying)
                                    }
                                }
                            }.frame(height: showSpectrum ? 66 : 48)
                        }
                        controls
                        if playback.hasHaptics { strengthControl }
                    }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12).background(LabTheme.panel)
                }
                .background(LabTheme.background).foregroundStyle(.white)
            }
            .navigationTitle("再生中").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { playback.pause(); dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                            .disabled(!playback.hasHaptics).accessibilityLabel("振動を調整").accessibilityIdentifier("music.settings")
                        Button { playback.pause() } label: { Image(systemName: "stop.fill").foregroundStyle(LabTheme.coral) }
                            .accessibilityLabel("停止").accessibilityIdentifier("music.stop")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if playback.visualizationTrack?.version == 3 {
                showSpectrum = false
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                ScrollView { settingsPanel.padding(16) }.background(LabTheme.background)
                    .navigationTitle("振動を調整").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { showSettings = false } } }
            }.preferredColorScheme(.dark)
        }
        .onDisappear { playback.pause() }
    }

    @ViewBuilder private var mediaPlayer: some View {
        if let selection = playback.selection {
            if let videoID = selection.videoID {
                YouTubeMusicPlayer(videoID: videoID, playback: playback).id(selection.id)
            } else if playback.containsVideo { VideoPlayer(player: playback.player) }
            else { MusicArtwork(selection: selection).padding(10) }
        } else {
            Image(systemName: "music.note").font(.system(size: 40)).foregroundStyle(LabTheme.muted)
        }
    }

    private var songHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(playback.hasHaptics ? "保存した振動を使用" : "映像・音声のみ", systemImage: playback.hasHaptics ? "waveform" : "play.rectangle")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(LabTheme.mint)
                Spacer()
                if playback.selection?.kind == .youtube, let url = URL(string: playback.selection?.url ?? "") {
                    Link("YouTubeで開く", destination: url).font(.system(size: 11)).foregroundStyle(LabTheme.muted)
                }
            }
            Text(playback.selection?.title ?? "曲を選んでください").font(.system(size: 21, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Text(playback.selection?.artist ?? "").font(.system(size: 13)).foregroundStyle(LabTheme.muted)
            if let analysis = playback.visualizationTrack?.analysis {
                Text(analysis.engine == "device"
                     ? "iPhone · \(analysis.quality?.title ?? "高速") · \(String(format: "%.1f", analysis.processingSeconds ?? analysis.elapsedSeconds))秒で解析"
                     : analysis.style == .arranged ? "PCでAI解析・振動を編曲" : "PCで精密解析")
                    .font(.system(size: 11)).foregroundStyle(LabTheme.muted)
                    .accessibilityIdentifier("music.analysisSummary")
            }
        }
    }

    private func arrangementPanel(_ score: MusicArrangementScore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("曲の展開と振動のモチーフ").font(.system(size: 13, weight: .semibold))
            if let current = score.sections.first(where: { $0.start <= playback.position && playback.position < $0.end }) {
                Text("\(sectionTitle(current.label)) · \(current.family == "drive" ? "推進するリズム" : current.family == "sway" ? "うねる持続" : "脈打つリズム")")
                    .font(.system(size: 12)).foregroundStyle(LabTheme.mint)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(score.sections) { section in
                        Button { playback.seek(to: section.start) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sectionTitle(section.label))
                                Text(musicTime(section.start)).font(.system(size: 10, design: .monospaced))
                            }.font(.system(size: 11)).padding(10)
                                .background(section.label == "chorus" ? LabTheme.mint.opacity(0.15) : LabTheme.elevated,
                                            in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).disabled(!playback.isReady)
                    }
                }
            }.scrollIndicators(.hidden)
            Text("曲の区間はAIの推定です。持続とアクセントを重ねて再生します。")
                .font(.system(size: 10)).foregroundStyle(LabTheme.muted)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("music.arrangement")
    }

    private func sectionTitle(_ label: String) -> String {
        switch label {
        case "chorus": return "サビ"
        case "verse": return "メロ"
        case "bridge": return "展開"
        case "intro": return "イントロ"
        case "outro", "end": return "終わり"
        case "inst", "solo": return "間奏"
        case "break": return "ブレイク"
        default: return "始まり"
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Slider(value: Binding(get: { min(max(0, playback.position), max(0.01, playback.duration)) },
                                  set: { playback.seek(to: $0) }), in: 0...max(0.01, playback.duration))
                .tint(LabTheme.mint).disabled(!playback.isReady || playback.duration <= 0)
                .accessibilityLabel("再生位置").accessibilityIdentifier("music.seek")
            HStack {
                Text(musicTime(playback.position))
                Spacer()
                Text(playback.isBuffering ? "読み込み待ち" : musicTime(playback.duration))
            }.font(.system(size: 11, design: .monospaced)).foregroundStyle(LabTheme.muted)
            HStack(spacing: 36) {
                Button { playback.seek(to: playback.position - 10) } label: { Image(systemName: "gobackward.10").font(.system(size: 25)) }
                    .accessibilityLabel("10秒戻す").disabled(!playback.isReady)
                Button { playback.toggle() } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 25, weight: .bold)).foregroundStyle(LabTheme.background)
                        .frame(width: 60, height: 60).background(LabTheme.mint, in: Circle())
                }
                .disabled(!playback.isReady).opacity(playback.isReady ? 1 : 0.45)
                .accessibilityLabel(playback.isPlaying ? "一時停止" : "音楽を再生").accessibilityIdentifier("music.play")
                Button { playback.seek(to: playback.position + 10) } label: { Image(systemName: "goforward.10").font(.system(size: 25)) }
                    .accessibilityLabel("10秒進める").disabled(!playback.isReady)
            }.frame(maxWidth: .infinity).foregroundStyle(LabTheme.muted)
            if !playback.isReady { Text("プレーヤーを準備しています").font(.system(size: 12)).foregroundStyle(LabTheme.muted) }
            if playback.hasHaptics, !playback.renderer.supported {
                Text("振動の体験には対応するiPhone実機が必要です。").font(.system(size: 12)).foregroundStyle(LabTheme.muted)
            }
        }
    }

    private var strengthControl: some View {
        VStack(spacing: 2) {
            HStack {
                Text("全体の強さ").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(Int((playback.settings.gain * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(LabTheme.mint)
                    .accessibilityIdentifier("music.gainValue")
            }
            HStack(spacing: 8) {
                Text("オフ")
                Slider(value: settingsBinding.gain, in: MusicSettings.gainRange, step: 0.05)
                    .tint(LabTheme.mint).accessibilityLabel("全体の強さ")
                    .accessibilityValue("\(Int((playback.settings.gain * 100).rounded()))%")
                    .accessibilityIdentifier("music.gain")
                Text("400%")
            }.font(.system(size: 9)).foregroundStyle(LabTheme.muted)
        }
    }

    private var settingsBinding: Binding<MusicSettings> {
        Binding(get: { playback.settings }, set: { settings in
            guard let id = playback.selection?.id else { return }
            library.saveSettings(settings, id: id)
            playback.settings = library.settings(for: id)
        })
    }

    private var hasIndividualSettings: Bool {
        playback.selection.flatMap { library.record(for: $0) }?.hasIndividualSettings == true
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let record = playback.selection.flatMap({ library.record(for: $0) }) {
                Text("解析方法の切り替え").font(.system(size: 16, weight: .semibold))
                if let selected = record.analysisVariants.first(where: { $0.id == record.selectedVariantID }) {
                    Text(selected.title).font(.system(size: 12)).foregroundStyle(LabTheme.mint)
                        .accessibilityIdentifier("music.activeAnalysis")
                }
                Picker("保存した解析結果", selection: Binding(get: { record.selectedVariantID ?? "" }, set: { id in
                    do {
                        let track = try library.selectVariant(id, for: record.id)
                        try playback.switchAnalysis(track, variantID: id)
                    } catch { playback.message = error.localizedDescription }
                })) {
                    ForEach(record.analysisVariants.reversed()) { variant in
                        Text("\(variant.title) · \(variant.dateText)").tag(variant.id)
                    }
                }.pickerStyle(.menu).accessibilityIdentifier("music.analysisVariant")
                Text("\(record.analysisVariants.count)件の解析結果を保存。再生位置を保って切り替え、次回も最後に選んだ結果を使います。")
                    .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                    .accessibilityIdentifier("music.analysisCount")
                NavigationLink("解析結果を選んで削除") { MusicAnalysisDeletionView(recordID: record.id) }
                    .accessibilityIdentifier("music.deleteAnalyses")
                Divider()
            }
            Text(hasIndividualSettings ? "この曲の個別設定" : "グローバル設定を使用中")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(LabTheme.mint)
                .accessibilityIdentifier("music.settingsScope")
            Button("グローバルに戻す") {
                guard let id = playback.selection?.id else { return }
                library.resetSettingsToGlobal(id: id)
                playback.settings = library.settings(for: id)
            }.disabled(!hasIndividualSettings).accessibilityIdentifier("music.resetToGlobal")
            Button("この調整をグローバルにする") {
                guard let id = playback.selection?.id else { return }
                library.saveGlobalSettings(playback.settings, adoptingFor: id)
                playback.settings = library.settings(for: id)
            }.disabled(!hasIndividualSettings).accessibilityIdentifier("music.promoteToGlobal")
            NavigationLink("グローバル設定を編集") { GlobalMusicSettingsView() }
                .accessibilityIdentifier("music.globalSettings")
            Text("ここで調整すると、この曲だけの設定として保存します。グローバルに戻すと、以降の共通設定の変更にも追従します。")
                .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
            MusicVibrationSettingsEditor(settings: settingsBinding, arranged: playback.visualizationTrack?.version == 3)
        }.tint(LabTheme.mint).labPanel()
    }

}

struct YouTubeAccountView: View {
    @EnvironmentObject private var youtube: YouTubeAccount
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "play.rectangle.fill").font(.system(size: 38)).foregroundStyle(LabTheme.coral)
                    Text("YouTubeとつなぐ").font(.system(size: 25, weight: .bold))
                    if youtube.connected { connectedPanel }
                    else {
                        Text("Googleにログインして、自分の再生リストから動画を選べます。パスワードはGoogleの認証画面で入力します。")
                            .font(.system(size: 14)).foregroundStyle(LabTheme.muted).lineSpacing(4)
                        if !youtube.configured {
                            Text("このビルドにはGoogleログインの設定が入っていません。動画検索・音源ファイル・アプリ内リストは利用できます。")
                                .font(.system(size: 13)).foregroundStyle(LabTheme.coral).labPanel()
                                .accessibilityIdentifier("music.oauthNotConfigured")
                        }
                        PrimaryButton(title: youtube.authorizing ? "ログイン中…" : "Googleでログイン", symbol: "person.crop.circle") {
                            Task { await youtube.signIn() }
                        }.disabled(!youtube.configured || youtube.authorizing)
                    }
                    if let message = youtube.message { MusicMessage(text: message) { youtube.message = nil } }
                    Text("YouTubeの視聴履歴は公式APIから取得できません。このアプリの再生履歴と、振動作成済みリストは端末に保存します。")
                        .font(.system(size: 12)).foregroundStyle(LabTheme.muted).lineSpacing(4)
                    VStack(alignment: .leading, spacing: 12) {
                        Link("YouTube利用規約", destination: URL(string: "https://www.youtube.com/t/terms")!)
                        Link("Googleのプライバシーポリシー", destination: URL(string: "https://policies.google.com/privacy")!)
                        Link("Googleアカウントの接続管理", destination: URL(string: "https://myaccount.google.com/connections")!)
                    }.font(.system(size: 12)).foregroundStyle(LabTheme.mint)
                    Text("振動・音源・履歴はこの端末で管理します。Googleの認証情報はKeychainに保存します。自動同期を有効にすると、作成済み動画のIDをYouTubeの専用リストへ送信します。")
                        .font(.system(size: 11)).foregroundStyle(LabTheme.muted).lineSpacing(3)
                }.padding(24)
            }
            .background(LabTheme.background).foregroundStyle(.white)
            .navigationTitle("アカウント").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }

    private var connectedPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(youtube.accountTitle, systemImage: "checkmark.circle.fill").foregroundStyle(LabTheme.mint)
            Toggle("作成済み動画をYouTubeに自動追加", isOn: Binding(get: { youtube.autoSync }, set: { enabled in
                if enabled { Task { await youtube.enableSync(records: library.records) } }
                else { youtube.disableSync() }
            })).tint(LabTheme.mint).font(.system(size: 14)).disabled(youtube.authorizing)
                .accessibilityIdentifier("music.autoSync")
            Text("非公開の「触感ラボ・振動作成済み」を作り、振動が保存できた動画を追加します。アプリで曲を削除すると、自動同期が有効な間は専用リストからも外します。")
                .font(.system(size: 12)).foregroundStyle(LabTheme.muted).lineSpacing(4)
            Text(youtube.syncStatus).font(.system(size: 12)).foregroundStyle(LabTheme.muted)
            if youtube.syncing { ProgressView().tint(LabTheme.mint) }
            if youtube.autoSync {
                Button("同期を再試行") { youtube.synchronize(records: library.records, force: true) }
                    .disabled(youtube.syncing).foregroundStyle(LabTheme.mint)
            }
            if let url = youtube.managedPlaylistURL { Link("YouTubeの作成済みリストを開く", destination: url).foregroundStyle(LabTheme.mint) }
            Button("Googleとの接続を解除", role: .destructive) { youtube.disconnect() }
                .font(.system(size: 13)).foregroundStyle(LabTheme.coral)
        }.labPanel()
    }
}
