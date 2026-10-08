import SwiftUI
import UniformTypeIdentifiers

private struct MusicPreparationRequest: Identifiable {
    let selection: MusicSelection
    var audioURL: URL?
    var id: String { selection.id }
}

struct MusicView: View {
    @Binding var tab: PlayerTab
    @Binding var showAccount: Bool
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var playback: MusicPlayback
    @EnvironmentObject private var haptics: HapticController
    @EnvironmentObject private var youtube: YouTubeAccount
    @EnvironmentObject private var preferences: AnalysisPreferences
    @EnvironmentObject private var presentation: MusicPlayerPresentation
    @StateObject private var search = YouTubeSearch()
    @State private var showingPrepared = false
    @State private var playAfterPreparation: MusicSelection?
    @State private var pending: MusicPreparationRequest?
    @State private var deleting: MusicRecord?
    @State private var openPlayerAfterDismiss = false
    @State private var showPreparation = false
    @State private var preparationSelection: MusicSelection?
    @State private var playerAfterPreparation: MusicSelection?
    @FocusState private var urlFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .search: searchPanel
                    case .history:
                        Text("履歴").font(.system(size: 22, weight: .bold))
                        songList(library.history, empty: "まだ再生履歴がありません", detail: "このアプリで再生した曲がここに並びます。")
                    case .playlists: playlistPanel
                    }
                    if let message = library.message { MusicMessage(text: message) { library.message = nil } }
                    if playback.selection != nil { currentSongPanel }
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let progress = library.preparation {
                MusicPreparationBanner(progress: progress) {
                    urlFocused = false
                    preparationSelection = progress.selection
                    showPreparation = true
                }
            }
        }
        .sheet(item: $pending, onDismiss: {
            if openPlayerAfterDismiss { openPlayerAfterDismiss = false; presentation.expand() }
            else if let progress = library.preparation {
                preparationSelection = progress.selection
                showPreparation = true
            } else { playAfterPreparation = nil }
        }) { request in
            MusicPreparationView(selection: request.selection, initialAudio: request.audioURL) {
                open(request.selection, withHaptics: false)
            }
            .environmentObject(library)
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPreparation, onDismiss: {
            if let selection = playerAfterPreparation {
                playerAfterPreparation = nil
                open(selection, withHaptics: true)
            }
        }) {
            MusicPreparationStatusView(selection: preparationSelection) {
                playAfterPreparation = nil
                library.cancelPreparation()
                showPreparation = false
            }
            .environmentObject(library)
        }
        .sheet(item: $deleting) { record in
            NavigationStack { MusicAnalysisDeletionView(recordID: record.id) }
                .environmentObject(library).preferredColorScheme(.dark)
        }
        .onChange(of: library.recentlyPreparedID) { id in
            if let id {
                pending = nil
                let wasShowingPreparation = showPreparation
                showPreparation = false
                if let selection = playAfterPreparation, selection.id == id {
                    playAfterPreparation = nil
                    if wasShowingPreparation { playerAfterPreparation = selection }
                    else { open(selection, withHaptics: true) }
                }
            }
        }
        .onChange(of: library.records) { records in
            youtube.synchronize(records: records)
            refreshPlaybackSettings()
        }
        .onChange(of: library.globalSettings) { _ in refreshPlaybackSettings() }
        .onChange(of: tab) { _ in urlFocused = false }
        .onChange(of: showAccount) { showing in if showing { urlFocused = false } }
        .task {
            playback.onPlay = { [weak library] selection in library?.saveHistory(selection) }
            if youtube.connected { await youtube.loadPlaylists() }
            youtube.synchronize(records: library.records, force: true)
        }
    }

    private var currentSongPanel: some View {
        Button { urlFocused = false; presentation.expand() } label: {
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

    private var playlistPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            if showingPrepared {
                Button { showingPrepared = false } label: {
                    Label("再生リスト一覧", systemImage: "chevron.left")
                        .font(.system(size: 13)).foregroundStyle(LabTheme.mint)
                }.accessibilityIdentifier("music.playlistsBack")
                Text("作成済み").font(.system(size: 22, weight: .bold))
                songList(library.prepared, empty: "まだ振動がありません", detail: "検索から動画を選ぶと、振動を作成してここに保存します。")
            } else {
                Text("再生リスト").font(.system(size: 22, weight: .bold))
                Button { showingPrepared = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "waveform").font(.system(size: 24)).foregroundStyle(LabTheme.mint)
                            .frame(width: 48, height: 48)
                            .background(LabTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("作成済み").font(.system(size: 15, weight: .semibold))
                            Text("\(library.prepared.count)曲 · 保存した振動")
                                .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(LabTheme.muted)
                    }.padding(16).background(LabTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityIdentifier("music.preparedPlaylist")
                youtubePanel
            }
        }
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(LabTheme.muted)
                TextField("YouTubeを検索", text: $search.query)
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
            if search.canGoBack {
                Button { urlFocused = false; search.back() } label: {
                    Label("前の一覧に戻る", systemImage: "chevron.left").font(.system(size: 13)).foregroundStyle(LabTheme.mint)
                }.accessibilityIdentifier("youtube.browserBack")
            }
            if let target = search.target {
                Text(target.title).font(.system(size: 16, weight: .semibold))
                if case .channel(_, let tab) = target {
                    Picker("チャンネルの一覧", selection: Binding(get: { tab }, set: { search.channelTab($0, account: youtube) })) {
                        ForEach(YouTubeChannelTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("youtube.channelTabs")
                }
            }
            if let message = search.message { MusicMessage(text: message) { search.message = nil } }
            if search.results.isEmpty && !search.searching {
                MusicEmptyState(title: search.searchedQuery == nil ? "好きな音楽を探そう" : "選択できる項目がありません",
                                detail: search.searchedQuery == nil ? "曲名やチャンネル名で検索して、動画・チャンネル・再生リストを選びます。" : "別のキーワードや一覧を試してください。",
                                symbol: "magnifyingglass")
            }
            LazyVStack(spacing: 0) {
                ForEach(search.results) { item in
                    if let selection = item.selection {
                        MusicSongRow(selection: selection, prepared: library.record(for: selection)?.isPrepared == true,
                                     action: { select(selection) })
                    } else {
                        YouTubeBrowseRow(item: item) { urlFocused = false; search.open(item, account: youtube) }
                    }
                }
            }
            if search.searching { ProgressView("YouTubeを読み込み中…").font(.system(size: 12)).tint(LabTheme.mint) }
            else if search.nextCursor != nil {
                Button("もっと読み込む") { search.more(account: youtube) }.foregroundStyle(LabTheme.mint)
                    .accessibilityIdentifier("youtube.browserMore")
            }
        }
    }

    private func songList(_ records: [MusicRecord], empty: String, detail: String) -> some View {
        VStack(spacing: 10) {
            if records.isEmpty {
                MusicEmptyState(title: empty, detail: detail, symbol: tab == .history ? "clock" : "waveform")
            }
            ForEach(records) { record in
                MusicSongRow(selection: record.selection, prepared: record.isPrepared, bytes: record.totalTrackBytes,
                             action: { select(record.selection) }, delete: { deleting = record },
                             regenerate: {
                                 playAfterPreparation = nil
                                 pending = MusicPreparationRequest(selection: record.selection, audioURL: library.disk.mediaURL(record))
                             })
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
        let record = library.record(for: selection)
        if record?.isPrepared == true, record?.requiresAudioReanalysis != true {
            playAfterPreparation = nil
            open(selection, withHaptics: true)
        } else {
            guard library.preparation == nil else { library.message = "解析中の曲が終わってから選んでください。"; return }
            playback.pause()
            haptics.stop()
            urlFocused = false
            playAfterPreparation = selection
            pending = MusicPreparationRequest(selection: selection, audioURL: record.flatMap { library.disk.mediaURL($0) })
        }
    }

    private func open(_ selection: MusicSelection, withHaptics: Bool) {
        let record = library.record(for: selection)
        do {
            let track = withHaptics ? try record.map { try library.disk.track($0) } : nil
            haptics.stop()
            if playback.selection?.id == selection.id, playback.hasHaptics == withHaptics {
                if let track, let variantID = record?.selectedVariantID, playback.analysisVariantID != variantID {
                    try playback.switchAnalysis(track, variantID: variantID)
                }
                playback.settings = library.settings(for: selection.id)
            } else {
                playback.load(record?.selection ?? selection, track: track,
                              mediaURL: record.flatMap { library.disk.mediaURL($0) }, settings: library.settings(for: selection.id),
                              variantID: withHaptics ? record?.selectedVariantID : nil)
            }
            if pending != nil { openPlayerAfterDismiss = true; pending = nil }
            else { urlFocused = false; presentation.expand() }
        } catch {
            library.message = error.localizedDescription
            pending = MusicPreparationRequest(selection: selection, audioURL: record.flatMap { library.disk.mediaURL($0) })
        }
    }
    private func refreshPlaybackSettings() {
        guard let id = playback.selection?.id else { return }
        if playback.hasHaptics {
            guard let record = library.records.first(where: { $0.id == id }) else { playback.stop(); return }
            if let variantID = record.selectedVariantID, playback.analysisVariantID != variantID {
                do { try playback.switchAnalysis(library.disk.track(record), variantID: variantID) }
                catch { playback.message = error.localizedDescription }
            }
        }
        let settings = library.settings(for: id)
        if playback.settings != settings { playback.settings = settings }
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
                    if let regenerate { Button(action: regenerate) { Label("別の解析を追加", systemImage: "waveform.badge.plus") } }
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
