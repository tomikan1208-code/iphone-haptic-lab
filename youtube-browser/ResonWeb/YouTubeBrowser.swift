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
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
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
        }]
        load(BrowserPage.search.url)
    }

    func open(_ page: BrowserPage) { self.page = page; load(page.url) }
    func search() { page = .search; load(BrowserNavigation.destination(for: query)) }
    func account() { load(URL(string: "https://www.youtube.com/account")!) }
    func reload() { load(currentURL) }
    func back() { webView.goBack() }
    func openInSafari() { UIApplication.shared.open(currentURL) }

    private func load(_ url: URL) {
        currentURL = url
        error = nil
        if fixture {
            #if DEBUG
            let heading = url.path == "/feed/history" ? "視聴履歴" : url.path == "/feed/playlists" ? "あなたの再生リスト" : "YouTube"
            webView.loadHTMLString("""
            <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
            <style>html,body{margin:0;background:#0f0f0f;color:white;font:16px system-ui}header{padding:18px;font-size:24px;font-weight:700}
            .video{margin:16px;height:175px;display:flex;align-items:center;justify-content:center;background:linear-gradient(135deg,#18232b,#3d2442);border-radius:12px;font-size:42px}
            p{margin:16px;color:#aaa}a{color:#9cddce}</style></head><body><header>\(heading)</header><div class="video">▶</div>
            <p>UI Preview · オフラインの画面確認用</p><p><a href="https://www.youtube.com/watch?v=lkiV3U0GfGg">Preview video</a></p></body></html>
            """, baseURL: url)
            #endif
        } else { webView.load(URLRequest(url: url)) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if !fixture, let url = webView.url { currentURL = url }
        loading = false
        canGoBack = webView.canGoBack
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { self.error = "ページが中断されました。再読み込みしてください。" }
    private func report(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
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
}

struct YouTubeWebsite: UIViewRepresentable {
    @ObservedObject var browser: YouTubeBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
