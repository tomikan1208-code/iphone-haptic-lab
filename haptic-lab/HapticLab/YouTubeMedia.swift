import Foundation
import SwiftUI
import YouTubeKit

enum YouTubeSearchService {
    static func search(_ query: String) async throws -> [MusicSelection] {
        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [.init(name: "search_query", value: query), .init(name: "hl", value: "ja")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("ja,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              response.url?.host == "www.youtube.com", data.count <= 8 * 1_024 * 1_024,
              let html = String(data: data, encoding: .utf8) else {
            throw MusicError.network("YouTubeを検索できませんでした。通信を確認して再試行してください。")
        }
        return try parse(html)
    }

    // Extract balanced JSON, respecting quoted braces and escaped quotation marks.
    static func initialData(in html: String) throws -> Data {
        let pattern = #"(?:var\s+)?ytInitialData\s*=\s*|window\[\"ytInitialData\"\]\s*=\s*"#
        let expression = try NSRegularExpression(pattern: pattern)
        let source = html as NSString
        for match in expression.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let tail = source.substring(from: NSMaxRange(match.range))
            guard let start = tail.firstIndex(of: "{"), tail[..<start].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            var depth = 0, quoted = false, escaped = false
            for index in tail.indices where index >= start {
                let character = tail[index]
                if quoted {
                    if escaped { escaped = false }
                    else if character == "\\" { escaped = true }
                    else if character == "\"" { quoted = false }
                } else if character == "\"" { quoted = true }
                else if character == "{" { depth += 1 }
                else if character == "}" {
                    depth -= 1
                    if depth == 0 { return Data(tail[start...index].utf8) }
                }
            }
        }
        throw MusicError.network("検索結果を読み込めませんでした。Googleに接続して再試行してください。")
    }

    static func parse(_ html: String) throws -> [MusicSelection] {
        let root = try JSONSerialization.jsonObject(with: initialData(in: html)) as? [String: Any]
        let contents = root?["contents"] as? [String: Any]
        let search = contents?["twoColumnSearchResultsRenderer"] as? [String: Any]
        guard let primary = search?["primaryContents"] else {
            throw MusicError.network("検索結果を読み込めませんでした。Googleに接続して再試行してください。")
        }
        var results: [MusicSelection] = [], seen = Set<String>()
        func text(_ value: Any?) -> String {
            guard let value = value as? [String: Any] else { return "" }
            return value["simpleText"] as? String ?? (value["runs"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
        }
        func visit(_ value: Any, depth: Int) {
            guard depth < 32, results.count < 30 else { return }
            if let list = value as? [Any] { for item in list { visit(item, depth: depth + 1) }; return }
            guard let node = value as? [String: Any] else { return }
            if node.keys.contains(where: { $0.lowercased().contains("adslot") || $0 == "promotedSparklesWebRenderer" }) { return }
            if let video = node["videoRenderer"] as? [String: Any], let id = video["videoId"] as? String,
               MusicSelection.validVideoID(id), seen.insert(id).inserted {
                let badges = video["badges"] as? [[String: Any]] ?? []
                if badges.contains(where: { ($0["metadataBadgeRenderer"] as? [String: Any])?["style"] as? String == "BADGE_STYLE_TYPE_LIVE_NOW" }) { return }
                let title = text(video["title"])
                if var selection = try? MusicSelection.youtube(id: id, title: title, artist: text(video["ownerText"] ?? video["longBylineText"])) {
                    let parts = text(video["lengthText"]).split(separator: ":").compactMap { Double($0) }
                    if !parts.isEmpty { selection.duration = parts.reduce(0) { $0 * 60 + $1 } }
                    results.append(selection)
                }
                return
            }
            for key in node.keys.sorted() { if let child = node[key] { visit(child, depth: depth + 1) } }
        }
        visit(primary, depth: 0)
        return results
    }
}

@MainActor
final class YouTubeSearch: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [YouTubeBrowseItem] = []
    @Published private(set) var searching = false
    @Published private(set) var searchedQuery: String?
    @Published var message: String?
    @Published private(set) var target: YouTubeBrowseTarget?
    @Published private(set) var nextCursor: YouTubeBrowseCursor?
    private var history: [(YouTubeBrowseTarget, YouTubeBrowsePage)] = []
    private var task: Task<Void, Never>?
    private var revision = 0
    typealias Loader = @MainActor (YouTubeBrowseTarget, YouTubeBrowseCursor?) async throws -> YouTubeBrowsePage
    private var loader: Loader?

    init(loader: Loader? = nil) {
        self.loader = loader
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--youtube-browser-fixture") {
            self.loader = { target, _ in
                let channel = YouTubeBrowseItem(kind: .channel, resourceID: "UC8T8_deSUS97DWZeKO_TL9Q", title: "テストチャンネル")
                let playlist = YouTubeBrowseItem(kind: .playlist, resourceID: "PL-TestPlaylist", title: "テスト再生リスト")
                let video = YouTubeBrowseItem(kind: .video, resourceID: "lkiV3U0GfGg", title: "テスト動画", duration: 547)
                switch target {
                case .search: return .init(items: [channel, playlist, video])
                case .channel(_, .videos), .playlist: return .init(items: [video])
                case .channel(_, .playlists): return .init(items: [playlist])
                }
            }
        }
        #endif
    }

    var canGoBack: Bool { !history.isEmpty }

    func submit(account: YouTubeAccount) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        history = []
        searchedQuery = query
        load(.search(query), account: account)
    }

    func open(_ item: YouTubeBrowseItem, account: YouTubeAccount) {
        guard item.kind != .video else { return }
        if let target { history.append((target, .init(items: results, cursor: nextCursor))) }
        let next: YouTubeBrowseTarget = item.kind == .channel ? .channel(item, .videos) : .playlist(item)
        load(next, account: account)
    }

    func channelTab(_ tab: YouTubeChannelTab, account: YouTubeAccount) {
        guard case .channel(let channel, _) = target else { return }
        load(.channel(channel, tab), account: account)
    }

    func back() {
        guard let previous = history.popLast() else { return }
        task?.cancel(); revision += 1
        target = previous.0
        results = previous.1.items
        nextCursor = previous.1.cursor
        searching = false; message = nil
    }

    func more(account: YouTubeAccount) {
        guard let target, let cursor = nextCursor, !searching else { return }
        load(target, account: account, cursor: cursor)
    }

    private func load(_ target: YouTubeBrowseTarget, account: YouTubeAccount, cursor: YouTubeBrowseCursor? = nil) {
        task?.cancel(); revision += 1
        let revision = revision, loader = self.loader
        self.target = target
        searching = true; message = nil
        if cursor == nil { results = []; nextCursor = nil }
        task = Task { [weak self] in
            do {
                let page: YouTubeBrowsePage
                if let loader { page = try await loader(target, cursor) }
                else if case .search(let query) = target, query.lowercased().hasPrefix("https://") {
                    let selection = try await YouTubeAccount.metadata(for: MusicSelection.parse(query))
                    page = .init(items: [.video(selection)])
                } else {
                    page = try await account.browse(target, cursor: cursor)
                }
                try Task.checkCancellation()
                guard let self, self.revision == revision else { return }
                var seen = Set(self.results.map(\.id))
                self.results.append(contentsOf: page.items.filter { seen.insert($0.id).inserted })
                self.nextCursor = page.cursor
            } catch {
                guard let self, self.revision == revision, !Task.isCancelled else { return }
                self.message = error.localizedDescription
            }
            guard let self, self.revision == revision else { return }
            self.searching = false
            self.task = nil
        }
    }
}
