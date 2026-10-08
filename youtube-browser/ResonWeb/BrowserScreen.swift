import SwiftUI

enum WebTheme {
    static let background = Color(red: 0.035, green: 0.04, blue: 0.04)
    static let panel = Color(red: 0.11, green: 0.12, blue: 0.12)
    static let mint = Color(red: 0.118, green: 0.843, blue: 0.376)
}

struct BrowserScreen: View {
    @EnvironmentObject private var browser: YouTubeBrowser
    @EnvironmentObject private var library: MusicLibrary
    @EnvironmentObject private var haptics: BrowserHaptics
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: BrowserSheet?
    @State private var immersive = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if immersive {
                    Button { immersive = false } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }
                        .accessibilityLabel("バーを表示").accessibilityIdentifier("browser.restoreChrome")
                }
                Image(systemName: "waveform").font(.system(size: 24)).foregroundStyle(WebTheme.mint)
                Text("Reson Web").font(.system(size: 23, weight: .bold, design: .rounded)).tracking(0.5)
                Spacer()
                if !immersive {
                    Button { searchFocused = false; sheet = .menu } label: {
                        Image(systemName: "ellipsis").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
                    }.accessibilityLabel("メニュー").accessibilityIdentifier("browser.menu")
                    Button { searchFocused = false; browser.account() } label: {
                        Image(systemName: "person.crop.circle").font(.system(size: 25)).frame(width: 44, height: 44)
                    }.accessibilityLabel("YouTubeアカウント").accessibilityIdentifier("browser.account")
                }
            }.padding(.horizontal, 16).padding(.vertical, 5)
            if browser.page == .search && !immersive {
                HStack(spacing: 8) {
                    if browser.canGoBack {
                        Button { browser.back() } label: { Image(systemName: "chevron.left").frame(width: 30, height: 44) }
                            .accessibilityLabel("前のページ")
                    }
                    TextField("YouTubeで検索、または動画URL", text: $browser.query)
                        .font(.system(size: 14)).focused($searchFocused).submitLabel(.search)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit { search() }.accessibilityIdentifier("browser.searchQuery")
                    Button { search() } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }
                        .accessibilityLabel("検索").accessibilityIdentifier("browser.search")
                }.padding(.leading, 14).background(WebTheme.panel, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16).padding(.bottom, 10)
            }
            ZStack(alignment: .top) {
                YouTubeWebsite(browser: browser)
                if browser.loading { ProgressView().padding(10).background(WebTheme.panel, in: Capsule()) }
                if let error = browser.error {
                    VStack(spacing: 16) {
                        Text(error).font(.system(size: 14))
                        Button("再読み込み") { browser.reload() }
                    }.padding(24).background(WebTheme.panel, in: RoundedRectangle(cornerRadius: 16)).padding(20)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if !immersive {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--browser-haptics-fixture") {
                    Text(browser.playbackDiagnostic).font(.caption2).lineLimit(1)
                        .accessibilityIdentifier("browser.haptics.diagnostic")
                }
                #endif
                if haptics.selection != nil || library.preparation != nil { BrowserHapticBar(sheet: $sheet) }
                HStack(spacing: 0) {
                    ForEach(BrowserPage.allCases) { page in
                        Button { searchFocused = false; browser.open(page) } label: {
                            VStack(spacing: 4) {
                                Image(systemName: page.symbol).font(.system(size: 19))
                                Text(page.title).font(.system(size: 10, weight: .medium))
                            }.frame(maxWidth: .infinity).frame(height: 56)
                                .foregroundStyle(browser.page == page ? .white : .gray)
                        }.buttonStyle(.plain).accessibilityIdentifier("browser.tab.\(page.rawValue)")
                            .accessibilityAddTraits(browser.page == page ? .isSelected : [])
                    }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("browser.navigation")
            }
        }.background(WebTheme.background.ignoresSafeArea()).foregroundStyle(.white)
            .onChange(of: scenePhase) { phase in
                if phase == .background { haptics.setForeground(false) }
                else if phase == .active { haptics.setForeground(true) }
            }
            .sheet(item: $sheet) { item in
                switch item {
                case .preparation(let selection):
                    MusicPreparationView(selection: selection, initialAudio: nil, preview: { sheet = nil })
                case .adjustment(let selection):
                    BrowserHapticSettingsView(selection: selection, prepareAgain: { sheet = .preparation(selection) })
                case .progress:
                    BrowserPreparationProgressView()
                case .menu:
                NavigationStack {
                    List {
                        Section("振動") {
                            Toggle("YouTubeの再生に同期", isOn: $haptics.enabled).accessibilityIdentifier("browser.haptics.menuToggle")
                            NavigationLink { BrowserSavedHapticsView(close: { sheet = nil }) } label: { Label("保存した振動", systemImage: "waveform") }
                                .accessibilityIdentifier("browser.haptics.saved")
                            NavigationLink { GlobalMusicSettingsView() } label: { Label("グローバル振動設定", systemImage: "slider.horizontal.3") }
                            NavigationLink { AnalysisSettingsView() } label: { Label("解析方法・PCサーバー", systemImage: "desktopcomputer") }
                            if library.preparation != nil {
                                Button("作成の進捗を表示") { sheet = .progress }
                            }
                        }
                        Section {
                        if browser.canGoBack {
                            Button { sheet = nil; browser.back() } label: { Label("前のページに戻る", systemImage: "chevron.left") }
                                .accessibilityIdentifier("browser.back")
                        }
                        Button { sheet = nil; browser.reload() } label: { Label("ページを再読み込み", systemImage: "arrow.clockwise") }
                        Button { sheet = nil; browser.openInSafari() } label: { Label("Safariで開く", systemImage: "safari") }
                        Button { sheet = nil; immersive = true } label: { Label("バーをたたむ", systemImage: "arrow.up.left.and.arrow.down.right") }
                            .accessibilityIdentifier("browser.hideChrome")
                        }
                        Section {
                            Text("YouTubeへのログイン中は、YouTube側の履歴・再生リストを使えます。")
                            Text("作成した振動はこのアプリに保存します。次回から解析せずに動画へ同期できます。")
                                .foregroundStyle(.secondary)
                        }.font(.system(size: 13))
                    }.scrollContentBackground(.hidden).background(WebTheme.background)
                        .navigationTitle("メニュー").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { sheet = nil } } }
                }
                }
            }
    }
    private func search() { searchFocused = false; browser.search() }
}
