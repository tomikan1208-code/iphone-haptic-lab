import SwiftUI

enum PlayerTab: String, CaseIterable, Identifiable {
    case music, gallery
    var id: String { rawValue }
    var title: String { self == .music ? "音楽" : "振動サンプル" }
    var symbol: String { self == .music ? "play.rectangle.fill" : "waveform" }
}

struct ContentView: View {
    @EnvironmentObject private var haptics: HapticController
    @EnvironmentObject private var music: MusicPlayback
    @State private var tab: PlayerTab = .music
    @State private var showTools = false
    @State private var showPlayer = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill").font(.system(size: 24)).foregroundStyle(LabTheme.mint)
                Text("音楽プレイヤー").font(.system(size: 19, weight: .bold))
                Spacer()
                Button { showTools = true } label: {
                    Image(systemName: "ellipsis").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
                }.accessibilityLabel("メニュー").accessibilityIdentifier("player.menu")
            }.padding(.horizontal, 16).padding(.vertical, 5)
            if let message = haptics.message {
                MusicMessage(text: message) { haptics.message = nil }.padding(.horizontal, 16)
            }
            if tab == .music { MusicView() }
            else { ScrollView { GalleryView().padding(16) }.scrollIndicators(.hidden) }
            if music.selection != nil { miniPlayer }
            if tab == .gallery {
                HStack {
                    Text(haptics.activeName).font(.system(size: 12)).accessibilityIdentifier("playback.status")
                    Spacer()
                    Button("停止") { haptics.stop() }.foregroundStyle(LabTheme.coral)
                        .accessibilityIdentifier("playback.stop")
                }.padding(16).background(LabTheme.panel)
            }
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
            }.background(LabTheme.background).accessibilityElement(children: .contain).accessibilityIdentifier("player.navigation")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LabTheme.background.ignoresSafeArea())
        .foregroundStyle(.white)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: tab) { _ in haptics.stop(); music.suspend() }
        .sheet(isPresented: $showTools) { PlayerToolsView() }
        .sheet(isPresented: $showPlayer, onDismiss: { music.pause() }) { MusicPlayerScreen() }
    }

    private var miniPlayer: some View {
        VStack(spacing: 0) {
            HapticTimelineView(track: music.visualizationTrack, position: music.position, settings: music.settings,
                               compact: true, playing: music.isPlaying).frame(height: 36)
            HStack(spacing: 12) {
                Button { showPlayer = true } label: {
                    HStack(spacing: 10) {
                        MusicArtwork(selection: music.selection, compact: true).frame(width: 42, height: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(music.selection?.title ?? "").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text(musicTime(music.position) + " / " + musicTime(music.duration))
                                .font(.system(size: 10)).foregroundStyle(LabTheme.muted)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityIdentifier("player.expand")
                Button {
                    if music.selection?.kind == .youtube { showPlayer = true }
                    else { music.toggle() }
                } label: {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").frame(width: 36, height: 40)
                }.disabled(!music.isReady).accessibilityLabel(music.isPlaying ? "一時停止" : "音楽を再生")
                Button { haptics.stop(); music.stop() } label: {
                    Image(systemName: "xmark").frame(width: 32, height: 40)
                }.accessibilityLabel("再生を終了").accessibilityIdentifier("player.close")
            }.padding(.horizontal, 12).padding(.bottom, 4)
        }.background(LabTheme.panel).accessibilityIdentifier("player.miniPlayer")
    }
}

struct PlayerToolsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { AnalysisSettingsView() } label: { Label("解析方法・PCサーバー", systemImage: "desktopcomputer") }
                        .accessibilityIdentifier("menu.analysis")
                }
                Section("振動ツール") {
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
