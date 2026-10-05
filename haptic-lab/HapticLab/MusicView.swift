import SwiftUI
import UniformTypeIdentifiers

private enum MusicListSection: String, CaseIterable {
    case search = "検索", prepared = "作成済み", history = "履歴", youtube = "再生リスト"
}

private struct MusicPreparationRequest: Identifiable {
    let selection: MusicSelection
    var audioURL: URL?
    var id: String { selection.id }
}

struct MusicView: View {
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var playback: MusicPlayback
    @EnvironmentObject private var haptics: HapticController
    @EnvironmentObject private var youtube: YouTubeAccount
    @EnvironmentObject private var preferences: AnalysisPreferences
    @StateObject private var search = YouTubeSearch()
    @State private var section: MusicListSection = .search
    @State private var playAfterPreparation: MusicSelection?
    @State private var pending: MusicPreparationRequest?
    @State private var importing = false
    @State private var showPlayer = false
    @State private var showAccount = false
    @State private var deleting: MusicRecord?
    @State private var openPlayerAfterDismiss = false
    @FocusState private var urlFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inputPanel
                    if let progress = library.preparation { preparationPanel(progress) }
                    if let message = library.message { MusicMessage(text: message) { library.message = nil } }
                    if playback.selection != nil { currentSongPanel }
                    libraryPanel
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: urlFocused) { focused in
                if focused { withAnimation { proxy.scrollTo("music.searchInput", anchor: .top) } }
            }
        }
        .sheet(item: $pending, onDismiss: {
            if openPlayerAfterDismiss { openPlayerAfterDismiss = false; showPlayer = true }
        }) { request in
            MusicPreparationView(selection: request.selection, initialAudio: request.audioURL) {
                open(request.selection, withHaptics: false)
            }
            .environmentObject(library)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPlayer, onDismiss: { playback.pause() }) {
            MusicPlayerScreen().environmentObject(playback).environmentObject(library)
        }
        .sheet(isPresented: $showAccount) {
            YouTubeAccountView().environmentObject(youtube).environmentObject(library)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .movie], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                pending = MusicPreparationRequest(selection: MusicSelection.file(url), audioURL: url)
            } catch { library.message = error.localizedDescription }
        }
        .alert("この曲の保存データを削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("削除", role: .destructive) {
                guard let record = deleting else { return }
                if playback.selection?.id == record.id { playback.stop() }
                do { try library.delete(record); youtube.synchronize(records: library.records) }
                catch { library.message = error.localizedDescription }
                deleting = nil
            }
            Button("キャンセル", role: .cancel) { deleting = nil }
        } message: {
            Text("振動・調整値・このアプリの履歴を削除します。読み込んだ音源のアプリ内コピーも削除されます。")
        }
        .onChange(of: library.recentlyPreparedID) { id in
            if let id {
                pending = nil
                section = .prepared
                if let selection = playAfterPreparation, selection.id == id {
                    playAfterPreparation = nil
                    open(selection, withHaptics: true)
                }
            }
        }
        .onChange(of: library.records) { records in youtube.synchronize(records: records) }
        .onChange(of: section) { _ in urlFocused = false }
        .task {
            playback.onPlay = { [weak library] selection in library?.saveHistory(selection) }
            if youtube.connected { await youtube.loadPlaylists() }
            youtube.synchronize(records: library.records, force: true)
        }
    }

    private var inputPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("あなたの音楽").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { urlFocused = false; showAccount = true } label: {
                    Label(youtube.connected ? "接続済み" : "ログイン", systemImage: "person.crop.circle")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(LabTheme.mint)
                }
                .accessibilityIdentifier("music.account")
            }
            Button { urlFocused = false; importing = true } label: {
                Label("音楽・動画ファイルから選ぶ", systemImage: "folder")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(LabTheme.muted)
                    .padding(.vertical, 4)
            }
            .accessibilityIdentifier("music.import")
            Button {
                guard let url = Bundle.main.url(forResource: "MusicDemo", withExtension: "wav") else { return }
                let selection = MusicSelection(id: "bundled-music-demo", kind: .file, title: "Pulse Garden · 12秒のサンプル",
                                           artist: "オリジナルサンプル", url: "")
                if library.record(for: selection)?.isPrepared == true { open(selection, withHaptics: true) }
                else { pending = MusicPreparationRequest(selection: selection, audioURL: url) }
            } label: {
                Label("12秒のサンプルで試す", systemImage: "sparkles").font(.system(size: 12)).foregroundStyle(LabTheme.mint)
            }
            .accessibilityIdentifier("music.demo")
        }
        .padding(14).background(LabTheme.panel, in: RoundedRectangle(cornerRadius: 12))
    }

    private func preparationPanel(_ progress: MusicPreparationProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.badge.plus").foregroundStyle(LabTheme.mint)
                Text("振動を作成中").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(Int(progress.fraction * 100))%").font(.system(size: 12, design: .monospaced)).foregroundStyle(LabTheme.mint)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("経過 \(Int(context.date.timeIntervalSince(progress.startedAt)))秒" + progress.remainingText)
                    .font(.system(size: 11)).foregroundStyle(LabTheme.muted)
            }
            Text(progress.selection.title).font(.system(size: 13)).lineLimit(2)
            ProgressView(value: progress.fraction).tint(LabTheme.mint)
            HStack {
                Text(progress.message).font(.system(size: 11)).foregroundStyle(LabTheme.muted)
                Spacer()
                Button("キャンセル") { playAfterPreparation = nil; library.cancelPreparation() }.font(.system(size: 12)).foregroundStyle(LabTheme.coral)
                    .accessibilityIdentifier("music.cancelAnalysis")
            }
            Text("解析中はこのアプリを開いたままにしてください。")
                .font(.system(size: 11)).foregroundStyle(LabTheme.muted)
        }
        .labPanel().accessibilityIdentifier("music.analysisProgress")
    }

    private var currentSongPanel: some View {
        Button { showPlayer = true } label: {
            HStack(spacing: 12) {
                Image(systemName: playback.isPlaying ? "waveform" : "play.circle.fill")
                    .font(.system(size: 26)).foregroundStyle(LabTheme.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(playback.selection?.title ?? "").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(playback.hasHaptics ? "保存した振動と再生" : "映像・音声のみ")
                        .font(.system(size: 11)).foregroundStyle(LabTheme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(LabTheme.muted)
            }
        }
        .buttonStyle(.plain).labPanel().accessibilityIdentifier("music.nowPlaying")
    }

    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("ライブラリ").font(.system(size: 19, weight: .bold))
                Spacer()
                Text("\(library.prepared.count)曲の振動").font(.system(size: 12)).foregroundStyle(LabTheme.muted)
            }
            Picker("音楽リスト", selection: $section) {
                ForEach(MusicListSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).accessibilityIdentifier("music.librarySections")
            switch section {
            case .search: searchPanel
            case .prepared: songList(library.prepared, empty: "まだ振動がありません", detail: "検索から動画を選ぶと、振動を作成してここに保存します。")
            case .history: songList(library.history, empty: "まだ再生履歴がありません", detail: "このアプリで再生した曲がここに並びます。")
            case .youtube: youtubePanel
            }
        }
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(LabTheme.muted)
                TextField("YouTubeで曲・アーティストを検索", text: $search.query)
                    .font(.system(size: 14)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search).onSubmit { submitSearch() }.focused($urlFocused)
                    .accessibilityIdentifier("music.searchQuery")
                Button(action: submitSearch) {
                    if search.searching { ProgressView().tint(LabTheme.mint) }
                    else { Image(systemName: "arrow.right.circle.fill").font(.system(size: 25)).foregroundStyle(LabTheme.mint) }
                }
                .disabled(search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("YouTubeを検索").accessibilityIdentifier("music.search")
            }.padding(14).background(LabTheme.elevated, in: RoundedRectangle(cornerRadius: 24))
                .id("music.searchInput")
            if let message = search.message { MusicMessage(text: message) { search.message = nil } }
            if search.searching {
                Text("YouTubeを検索中…").font(.system(size: 12)).foregroundStyle(LabTheme.muted)
            } else if search.results.isEmpty {
                MusicEmptyState(title: search.searchedQuery == nil ? "好きな音楽を探そう" : "動画が見つかりませんでした",
                                detail: search.searchedQuery == nil ? "曲名やアーティスト名で検索して、動画を選びます。" : "別のキーワードで検索してみてください。",
                                symbol: "magnifyingglass")
            } else {
                Text("「\(search.searchedQuery ?? "")」の検索結果").font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                ForEach(search.results) { selection in
                    MusicSongRow(selection: selection, prepared: library.record(for: selection)?.isPrepared == true,
                                 action: { select(selection) })
                }
            }
        }.accessibilityIdentifier("music.searchResults")
    }

    private func songList(_ records: [MusicRecord], empty: String, detail: String) -> some View {
        VStack(spacing: 10) {
            if records.isEmpty {
                MusicEmptyState(title: empty, detail: detail, symbol: section == .history ? "clock" : "waveform")
            }
            ForEach(records) { record in
                MusicSongRow(selection: record.selection, prepared: record.isPrepared, bytes: record.trackBytes,
                             action: { select(record.selection) }, delete: { deleting = record },
                             regenerate: { pending = MusicPreparationRequest(selection: record.selection, audioURL: library.disk.mediaURL(record)) })
            }
        }
    }

    private var youtubePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !youtube.connected {
                MusicEmptyState(title: "再生リストから選ぶ", detail: "Googleにログインして、自分のYouTube再生リストを表示します。", symbol: "play.rectangle")
                PrimaryButton(title: "Googleでログイン", symbol: "person.crop.circle") { showAccount = true }
            } else {
                HStack {
                    Text(youtube.accountTitle).font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                    Spacer()
                    Button { Task { await youtube.loadPlaylists() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(youtube.loading).foregroundStyle(LabTheme.mint)
                }
                if let playlist = youtube.selectedPlaylist {
                    Button { youtube.closePlaylist() } label: {
                        Label("再生リスト一覧", systemImage: "chevron.left").font(.system(size: 13)).foregroundStyle(LabTheme.mint)
                    }
                    Text(playlist.snippet.title).font(.system(size: 16, weight: .semibold))
                    ForEach(youtube.playlistVideos) { selection in
                        MusicSongRow(selection: selection, prepared: library.record(for: selection)?.isPrepared == true,
                                     action: { select(selection) })
                    }
                    if youtube.playlistVideos.isEmpty, !youtube.loading {
                        Text("選択できる動画がありません。").font(.system(size: 13)).foregroundStyle(LabTheme.muted)
                    }
                    if youtube.nextVideoPage != nil { Button("もっと読み込む") { Task { await youtube.loadVideos(playlist, more: true) } }.disabled(youtube.loading) }
                } else {
                    ForEach(youtube.playlists) { playlist in
                        Button { Task { await youtube.loadVideos(playlist) } } label: {
                            HStack {
                                Image(systemName: "music.note.list").foregroundStyle(LabTheme.violet)
                                Text(playlist.snippet.title).font(.system(size: 14, weight: .medium)).multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(LabTheme.muted)
                            }.padding(16).background(LabTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain).disabled(youtube.loading)
                    }
                    if youtube.nextPlaylistPage != nil { Button("もっと読み込む") { Task { await youtube.loadPlaylists(more: true) } }.disabled(youtube.loading) }
                    if youtube.playlists.isEmpty, !youtube.loading { Text("再生リストがありません。").foregroundStyle(LabTheme.muted) }
                }
                if youtube.loading { ProgressView().tint(LabTheme.mint).frame(maxWidth: .infinity) }
                if let message = youtube.message { MusicMessage(text: message) { youtube.message = nil } }
            }
            Text("YouTube全体の視聴履歴は取得できません。「履歴」にはこのアプリで再生した曲が表示されます。")
                .font(.system(size: 11)).foregroundStyle(LabTheme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submitSearch() {
        urlFocused = false
        search.submit(account: youtube)
    }

    private func select(_ selection: MusicSelection) {
        if library.record(for: selection)?.isPrepared == true {
            playAfterPreparation = nil
            open(selection, withHaptics: true)
        } else if selection.kind == .youtube {
            guard library.preparation == nil else { library.message = "解析中の曲が終わってから選んでください。"; return }
            playback.pause()
            haptics.stop()
            library.prepare(selection, method: .device, style: preferences.style, profile: preferences.profile)
            if library.preparation?.selection.id == selection.id { playAfterPreparation = selection }
        } else { pending = MusicPreparationRequest(selection: selection) }
    }

    private func open(_ selection: MusicSelection, withHaptics: Bool) {
        let record = library.record(for: selection)
        do {
            let track = withHaptics ? try record.map { try library.disk.track($0) } : nil
            haptics.stop()
            playback.load(record?.selection ?? selection, track: track,
                          mediaURL: record.flatMap { library.disk.mediaURL($0) }, settings: record?.settings ?? MusicSettings())
            if pending != nil { openPlayerAfterDismiss = true; pending = nil }
            else { showPlayer = true }
        } catch {
            library.message = error.localizedDescription
            pending = MusicPreparationRequest(selection: selection, audioURL: record.flatMap { library.disk.mediaURL($0) })
        }
    }
}

struct MusicPreparationView: View {
    let selection: MusicSelection
    let initialAudio: URL?
    let preview: () -> Void
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var preferences: AnalysisPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var method: MusicAnalysisMethod = .device
    @State private var style: MusicGenerationStyle = .following
    @State private var profile: MusicArrangement = .standard
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
                    Picker("解析する場所", selection: $method) {
                        ForEach(MusicAnalysisMethod.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("analysis.method")
                    Picker("振動の作り方", selection: $style) {
                        ForEach(MusicGenerationStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("analysis.style")
                    Text(style.detail).font(.system(size: 13)).foregroundStyle(LabTheme.muted)
                    Picker("仕上げ", selection: $profile) {
                        ForEach(MusicArrangement.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("analysis.profile")
                    if profile == .orchestral {
                        Text("拍ごとのタップを控え、低音・クレッシェンド・余韻をなめらかな持続振動にします。")
                            .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                    }
                    Text(method == .pc
                         ? "PCが音源を取得・解析し、振動をPCとiPhoneへ保存します。次回の再生にはPCは不要です。YouTubeは公開動画のURLだけで作成できます。"
                         : selection.kind == .youtube
                           ? "このiPhoneで動画の音声を一時的に取得し、周波数を解析します。振動の保存後に音声を削除し、次回は保存した振動とYouTube動画を再生します。"
                           : "iPhone内で音源を解析し、振動を保存します。次回から解析せずに再生できます。")
                        .font(.system(size: 14)).foregroundStyle(LabTheme.muted).lineSpacing(5)
                    if method == .pc {
                        Button("PCの接続設定") { showPCSettings = true }.foregroundStyle(LabTheme.mint)
                    } else if selection.kind == .youtube {
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
            .navigationTitle("初回の準備").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
        .onAppear { method = selection.kind == .youtube ? .device : preferences.method; style = preferences.style; profile = preferences.profile }
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
                library.prepare(selection, audioFile: url, method: method, style: style, profile: profile, connection: preferences.connection)
                dismiss()
            } catch { library.message = error.localizedDescription }
        }
    }
    private func start() {
        errorText = nil
        preferences.method = method
        preferences.style = style
        preferences.profile = profile
        if method == .pc, preferences.connection == nil { showPCSettings = true; return }
        do {
            let audioURL = audioURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : try MusicSelection.audioDownloadURL(audioURLText)
            if selection.kind == .file && initialAudio == nil {
                importing = true
                return
            }
            library.prepare(selection, audioFile: initialAudio, audioDownloadURL: audioURL,
                            method: method, style: style, profile: profile, connection: preferences.connection)
            dismiss()
        } catch { errorText = error.localizedDescription }
    }
}

struct MusicSongRow: View {
    let selection: MusicSelection
    let prepared: Bool
    var bytes = 0
    let action: () -> Void
    var delete: (() -> Void)?
    var regenerate: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    MusicArtwork(selection: selection, compact: true).frame(width: 108, height: 68)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(selection.title).font(.system(size: 14, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        Text(selection.artist).font(.system(size: 11)).foregroundStyle(LabTheme.muted).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(prepared ? "振動作成済み" : "初回の振動を作成")
                            if let duration = selection.duration { Text("· \(musicTime(duration))") }
                            if bytes > 0 { Text("· \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))") }
                        }.font(.system(size: 10)).foregroundStyle(prepared ? LabTheme.mint : LabTheme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("music.song.\(selection.id)")
            if let delete {
                Menu {
                    if let regenerate { Button(action: regenerate) { Label("振動を作り直す", systemImage: "waveform.badge.plus") } }
                    Button(role: .destructive, action: delete) { Label("保存データを削除", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis").foregroundStyle(LabTheme.muted).frame(width: 30, height: 44) }
                .accessibilityLabel("\(selection.title)の操作")
            }
        }
        .padding(.vertical, 10)
    }
}

struct MusicEmptyState: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(LabTheme.muted)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(LabTheme.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 28).labPanel()
    }
}

struct MusicMessage: View {
    let text: String
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(LabTheme.mint)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark").foregroundStyle(LabTheme.muted).padding(4) }
                .accessibilityLabel("メッセージを閉じる")
        }.padding(14).background(LabTheme.elevated, in: RoundedRectangle(cornerRadius: 13))
    }
}
