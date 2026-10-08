import SwiftUI
import UIKit

enum PlayerTab: String, CaseIterable, Identifiable {
    case search, history, playlists
    var id: String { rawValue }
    var title: String {
        switch self {
        case .search: return "検索"
        case .history: return "履歴"
        case .playlists: return "再生リスト"
        }
    }
    var symbol: String {
        switch self {
        case .search: return "magnifyingglass"
        case .history: return "clock"
        case .playlists: return "music.note.list"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var haptics: HapticController
    @EnvironmentObject private var music: MusicPlayback
    @EnvironmentObject private var youtube: YouTubeAccount
    @EnvironmentObject private var presentation: MusicPlayerPresentation
    @State private var tab: PlayerTab = .search
    @State private var showTools = false
    @State private var showAccount = false

    var body: some View {
        GeometryReader { geometry in
            let miniHeight: CGFloat = music.containsVideo ? max(200, geometry.size.width * 9 / 16) + 52 : 88
            ZStack(alignment: .top) {
                browsing(miniHeight: music.selection == nil ? 0 : miniHeight)
                    .allowsHitTesting(!presentation.isExpanded)
                    .accessibilityHidden(presentation.isExpanded)
                if music.selection != nil {
                    // This host stays mounted when minimized or rotated, including its WKWebView.
                    MusicPlayerScreen(bottomInset: presentation.isExpanded ? geometry.safeAreaInsets.bottom : 0)
                        .frame(width: geometry.size.width, height: presentation.isExpanded
                               ? geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom : miniHeight)
                        .offset(y: presentation.isExpanded ? -geometry.safeAreaInsets.top
                                : geometry.size.height - 56 - miniHeight)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .background(LabTheme.background.ignoresSafeArea())
        .foregroundStyle(.white)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .statusBarHidden(presentation.isExpanded)
        .onChange(of: tab) { _ in haptics.stop() }
        .onChange(of: presentation.isExpanded) { expanded in
            if expanded { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
        .onChange(of: music.selection?.id) { id in if id == nil { presentation.minimize() } }
        .onChange(of: showTools) { showing in
            if showing { haptics.stop(); music.suspend() }
        }
        .sheet(isPresented: $showTools) { PlayerToolsView() }
        .sheet(isPresented: $showAccount) { YouTubeAccountView() }
    }

    private func browsing(miniHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform").font(.system(size: 24)).foregroundStyle(LabTheme.mint)
                Text("Reson").font(.system(size: 23, weight: .bold, design: .rounded)).tracking(0.5)
                Spacer()
                Button { showTools = true } label: {
                    Image(systemName: "ellipsis").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
                }.accessibilityLabel("メニュー").accessibilityIdentifier("player.menu")
                Button { showAccount = true } label: {
                    Image(systemName: youtube.connected ? "person.crop.circle.fill" : "person.crop.circle")
                        .font(.system(size: 25)).frame(width: 44, height: 44)
                        .foregroundStyle(youtube.connected ? LabTheme.mint : .white)
                }
                .accessibilityLabel("YouTubeアカウント")
                .accessibilityValue(youtube.connected ? "接続済み" : "未接続")
                .accessibilityIdentifier("music.account")
            }.padding(.horizontal, 16).padding(.vertical, 5)
            if let message = haptics.message {
                MusicMessage(text: message) { haptics.message = nil }.padding(.horizontal, 16)
            }
            MusicView(tab: $tab, showAccount: $showAccount)
            Color.clear.frame(height: miniHeight)
            HStack(spacing: 0) {
                ForEach(PlayerTab.allCases) { item in
                    Button { tab = item } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.symbol).font(.system(size: 19))
                            Text(item.title).font(.system(size: 10, weight: .medium))
                        }.frame(maxWidth: .infinity).padding(.vertical, 10)
                            .foregroundStyle(tab == item ? .white : LabTheme.muted)
                    }.buttonStyle(.plain).accessibilityIdentifier("tab.\(item.rawValue)")
                        .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }.frame(height: 56).background(LabTheme.background).accessibilityElement(children: .contain).accessibilityIdentifier("player.navigation")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlayerToolsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { GlobalMusicSettingsView() } label: { Label("グローバル振動設定", systemImage: "slider.horizontal.3") }
                        .accessibilityIdentifier("menu.globalSettings")
                    NavigationLink { AnalysisSettingsView() } label: { Label("解析方法・PCサーバー", systemImage: "desktopcomputer") }
                        .accessibilityIdentifier("menu.analysis")
                }
                Section("振動ツール") {
                    NavigationLink { tool(GalleryView(), title: "振動サンプル") } label: { Label("振動サンプル", systemImage: "waveform") }
                        .accessibilityIdentifier("menu.gallery")
                    NavigationLink { tool(ExperimentView(), title: "振動を調整") } label: { Label("振動を調整", systemImage: "slider.horizontal.3") }
                        .accessibilityIdentifier("tab.experiment")
                    NavigationLink { tool(TouchPadView(), title: "タッチパッド") } label: { Label("タッチパッド", systemImage: "hand.draw") }
                        .accessibilityIdentifier("tab.pad")
                    NavigationLink { tool(GuideView(), title: "使い方") } label: { Label("使い方", systemImage: "questionmark.circle") }
                        .accessibilityIdentifier("tab.guide")
                }
            }.scrollContentBackground(.hidden).background(LabTheme.background)
                .navigationTitle("メニュー").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
        }.tint(LabTheme.mint).preferredColorScheme(.dark)
    }
    private func tool<V: View>(_ view: V, title: String) -> some View { ToolScreen(title: title) { view } }
}

private struct ToolScreen<V: View>: View {
    let title: String
    @ViewBuilder let content: () -> V
    @EnvironmentObject private var haptics: HapticController
    var body: some View {
        VStack(spacing: 0) {
            ScrollView { content().padding(16) }
            HStack {
                Text(haptics.activeName).font(.system(size: 12)).accessibilityIdentifier("playback.status")
                Spacer()
                if title == "振動を調整" {
                    Button("再生") { haptics.play(PatternFactory.experiment(.saved())) }
                        .accessibilityIdentifier("experiment.quickPlay")
                }
                Button("停止") { haptics.stop() }.foregroundStyle(LabTheme.coral).accessibilityIdentifier("tools.stop")
            }.padding(16).background(LabTheme.panel)
        }.background(LabTheme.background).foregroundStyle(.white).navigationTitle(title)
            .onDisappear { haptics.stop() }
    }
}
