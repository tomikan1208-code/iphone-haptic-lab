import SwiftUI
import WebKit

enum BrowserPage: String, CaseIterable, Identifiable {
    case search, history, playlists
    var id: String { rawValue }
    var title: String {
        switch self { case .search: return "検索"; case .history: return "履歴"; case .playlists: return "再生リスト" }
    }
    var symbol: String {
        switch self { case .search: return "magnifyingglass"; case .history: return "clock"; case .playlists: return "music.note.list" }
    }
    var url: URL {
        let path: String
        switch self { case .search: path = "/"; case .history: path = "/feed/history"; case .playlists: path = "/feed/playlists" }
        return URL(string: "https://www.youtube.com" + path)!
    }
}

enum BrowserNavigation {
    static func isYouTube(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return false }
        return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
    }
    static func destination(for query: String) -> URL {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return BrowserPage.search.url }
        if let url = URL(string: text), isYouTube(url) { return url }
        if let url = URL(string: "https://" + text), isYouTube(url) { return url }
        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: text)]
        return components.url!
    }
    static func isInternal(_ url: URL) -> Bool {
        if isYouTube(url) { return true }
        guard url.scheme == "https", url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return false }
        return host == "google.com" || host.hasSuffix(".google.com")
    }
}

@MainActor
final class YouTubeBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var page: BrowserPage = .search
    @Published var query = ""
    @Published private(set) var loading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var currentURL = BrowserPage.search.url
    @Published private(set) var error: String?
    var onPlayback: ((WebPlaybackSnapshot) -> Void)?
    var onPlaybackDisconnected: (() -> Void)?
    private var playbackHandler: BrowserPlaybackHandler?
    #if DEBUG
    @Published private(set) var playbackDiagnostic = "観測スクリプトなし"
    #endif
    private var observations: [NSKeyValueObservation] = []
    private var fixture: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--browser-ui-fixture")
        #else
        return false
        #endif
    }

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        if let url = Bundle.main.url(forResource: "PlaybackObservation", withExtension: "js"),
           let script = try? String(contentsOf: url, encoding: .utf8) {
            #if DEBUG
            let fixture = ProcessInfo.processInfo.arguments.contains("--browser-ui-fixture")
            #else
            let fixture = false
            #endif
            configuration.userContentController.addUserScript(WKUserScript(
                source: script.replacingOccurrences(of: "__RESON_TEST_FIXTURE__", with: fixture ? "true" : "false"),
                injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .world(name: "ResonPlayback")))
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        #if DEBUG
        playbackDiagnostic = configuration.userContentController.userScripts.isEmpty ? "観測スクリプトなし" : "観測メッセージ待ち"
        #endif
        let handler = BrowserPlaybackHandler(browser: self)
        playbackHandler = handler
        configuration.userContentController.add(handler, contentWorld: .world(name: "ResonPlayback"), name: "resonPlayback")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.accessibilityIdentifier = "browser.website"
        observations = [webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.loading = self?.webView.isLoading ?? false }
        }, webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.canGoBack = self?.webView.canGoBack ?? false }
        }, webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                guard let self, !self.fixture, let url = self.webView.url else { return }
                self.currentURL = url
            }
        }]
        load(BrowserPage.search.url)
    }

    func open(_ page: BrowserPage) { self.page = page; load(page.url) }
    func search() { page = .search; load(BrowserNavigation.destination(for: query)) }
    func account() { load(URL(string: "https://www.youtube.com/account")!) }
    func reload() { load(currentURL) }
    func back() { webView.goBack() }
    func openInSafari() { UIApplication.shared.open(currentURL) }
    func openVideo(_ selection: MusicSelection) { page = .search; load(URL(string: selection.url)!) }

    private func load(_ url: URL) {
        onPlaybackDisconnected?()
        currentURL = url
        error = nil
        if fixture {
            #if DEBUG
            webView.loadHTMLString(BrowserFixtures.html(url: url), baseURL: url)
            #endif
        } else { webView.load(URLRequest(url: url)) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if !fixture, let url = webView.url { currentURL = url }
        loading = false
        canGoBack = webView.canGoBack
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { onPlaybackDisconnected?() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onPlaybackDisconnected?()
        self.error = "ページが中断されました。再読み込みしてください。"
    }
    private func report(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        onPlaybackDisconnected?()
        loading = false
        self.error = "ページを開けませんでした。接続を確認して再読み込みしてください。"
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "about" || navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if BrowserNavigation.isInternal(url) {
            if fixture, navigationAction.navigationType == .linkActivated { load(url); decisionHandler(.cancel) }
            else { decisionHandler(.allow) }
        } else {
            if navigationAction.navigationType == .linkActivated { UIApplication.shared.open(url) }
            decisionHandler(.cancel)
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if BrowserNavigation.isInternal(url) { load(url) }
            else { UIApplication.shared.open(url) }
        }
        return nil
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        let trusted = WebPlaybackSnapshot.acceptsOrigin(scheme: origin.protocol, host: origin.host,
                                                       mainFrame: message.frameInfo.isMainFrame)
        guard message.webView === webView, message.frameInfo.isMainFrame, trusted || fixture,
              let url = fixture ? currentURL : webView.url,
              let snapshot = WebPlaybackSnapshot.decode(message.body, pageURL: url) else {
            #if DEBUG
            if fixture {
                let values = message.body as? [String: Any] ?? [:]
                let diagnostic = "観測の検証待ち: \(values["url"] ?? "URLなし") · \(values["videoID"] ?? "IDなし")"
                if playbackDiagnostic != diagnostic { playbackDiagnostic = diagnostic }
            }
            #endif
            onPlaybackDisconnected?()
            return
        }
        #if DEBUG
        if fixture {
            let diagnostic = "観測中: \(snapshot.videoID ?? "動画なし")"
            if playbackDiagnostic != diagnostic { playbackDiagnostic = diagnostic }
        }
        #endif
        if !fixture { currentURL = snapshot.url }
        onPlayback?(snapshot)
    }
}

@MainActor
private final class BrowserPlaybackHandler: NSObject, WKScriptMessageHandler {
    weak var browser: YouTubeBrowser?
    init(browser: YouTubeBrowser) { self.browser = browser }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        browser?.receive(message)
    }
}

struct YouTubeWebsite: UIViewRepresentable {
    @ObservedObject var browser: YouTubeBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
