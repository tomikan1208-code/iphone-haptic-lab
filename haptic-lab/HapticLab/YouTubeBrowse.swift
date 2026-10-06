import Foundation

struct YouTubeBrowseItem: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case video, channel, playlist }
    let kind: Kind
    let resourceID: String
    let title: String
    var subtitle = ""
    var thumbnail: URL?
    var duration: Double?
    var videoOwner: String?
    var id: String { "\(kind.rawValue)-\(resourceID)" }
    var selection: MusicSelection? {
        guard kind == .video, var selection = try? MusicSelection.youtube(id: resourceID, title: title, artist: videoOwner ?? subtitle) else { return nil }
        selection.duration = duration
        return selection
    }

    static func video(_ selection: MusicSelection) -> YouTubeBrowseItem {
        .init(kind: .video, resourceID: selection.videoID ?? "", title: selection.title,
              subtitle: selection.artist, thumbnail: selection.videoID.flatMap { URL(string: "https://i.ytimg.com/vi/\($0)/hqdefault.jpg") },
              duration: selection.duration)
    }

    static func validID(_ id: String, kind: Kind) -> Bool {
        switch kind {
        case .video: return MusicSelection.validVideoID(id)
        case .channel: return id.range(of: "^UC[A-Za-z0-9_-]{22}$", options: .regularExpression) != nil
        case .playlist: return id.range(of: "^[A-Za-z0-9_-]{2,150}$", options: .regularExpression) != nil
        }
    }
}

enum YouTubeChannelTab: String, CaseIterable { case videos = "動画", playlists = "再生リスト" }

enum YouTubeBrowseTarget: Equatable {
    case search(String)
    case channel(YouTubeBrowseItem, YouTubeChannelTab)
    case playlist(YouTubeBrowseItem)
    var title: String {
        switch self { case .search(let query): return "「\(query)」の検索結果"
        case .channel(let item, _), .playlist(let item): return item.title }
    }
}

struct YouTubeBrowseCursor: Equatable, Sendable {
    let token: String
    var clientVersion: String?
    var visitorData: String?
    var apiKey: String?
    var playlistID: String?
}

struct YouTubeBrowsePage: Equatable, Sendable {
    var items: [YouTubeBrowseItem] = []
    var cursor: YouTubeBrowseCursor?
}

enum YouTubeBrowseService {
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"

    static func load(_ target: YouTubeBrowseTarget, cursor: YouTubeBrowseCursor? = nil) async throws -> YouTubeBrowsePage {
        var request: URLRequest
        if let cursor {
            guard let version = cursor.clientVersion else { throw MusicError.invalidURL }
            let endpoint: String
            if case .search = target { endpoint = "search" } else { endpoint = "browse" }
            var components = URLComponents(string: "https://www.youtube.com/youtubei/v1/\(endpoint)")!
            if let key = cursor.apiKey { components.queryItems = [.init(name: "key", value: key)] }
            request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            var client = ["clientName": "WEB", "clientVersion": version, "hl": "ja", "gl": "JP"]
            client["visitorData"] = cursor.visitorData
            request.httpBody = try JSONSerialization.data(withJSONObject: ["context": ["client": client], "continuation": cursor.token])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "X-YouTube-Client-Name")
            request.setValue(version, forHTTPHeaderField: "X-YouTube-Client-Version")
            request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        } else {
            var components = URLComponents(string: "https://www.youtube.com")!
            var query = [URLQueryItem(name: "hl", value: "ja")]
            switch target {
            case .search(let text): components.path = "/results"; query.append(.init(name: "search_query", value: text))
            case .channel(let item, let tab):
                guard YouTubeBrowseItem.validID(item.resourceID, kind: .channel) else { throw MusicError.invalidURL }
                components.path = "/channel/\(item.resourceID)/\(tab == .videos ? "videos" : "playlists")"
            case .playlist(let item):
                guard YouTubeBrowseItem.validID(item.resourceID, kind: .playlist) else { throw MusicError.invalidURL }
                components.path = "/playlist"; query.append(.init(name: "list", value: item.resourceID))
            }
            components.queryItems = query
            request = URLRequest(url: components.url!)
        }
        request.timeoutInterval = 30
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("ja,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.url?.host == "www.youtube.com", data.count <= 8 * 1_024 * 1_024 else {
            throw MusicError.network("YouTubeを読み込めませんでした。通信を確認して再試行してください。")
        }
        let requestedTab: YouTubeChannelTab?
        if case .channel(_, let tab) = target { requestedTab = tab } else { requestedTab = nil }
        var page: YouTubeBrowsePage
        if let cursor { page = try parseJSON(data, context: cursor, requestedTab: requestedTab) }
        else {
            guard let html = String(data: data, encoding: .utf8) else { throw MusicError.network("YouTubeの結果を読み込めませんでした。") }
            page = try parse(html, requestedTab: requestedTab)
        }
        if case .channel(let channel, .videos) = target {
            for index in page.items.indices where page.items[index].kind == .video { page.items[index].videoOwner = channel.title }
        }
        return page
    }

    static func parse(_ html: String, requestedTab: YouTubeChannelTab? = nil) throws -> YouTubeBrowsePage {
        func config(_ key: String) -> String? {
            guard let expression = try? NSRegularExpression(pattern: "\"\(key)\"\\s*:\\s*\"([^\"]+)\""),
                  let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        }
        let context = YouTubeBrowseCursor(token: "", clientVersion: config("INNERTUBE_CLIENT_VERSION"),
                                           visitorData: config("VISITOR_DATA"), apiKey: config("INNERTUBE_API_KEY"))
        return try parseJSON(YouTubeSearchService.initialData(in: html), context: context, requestedTab: requestedTab)
    }

    static func parseJSON(_ data: Data, context: YouTubeBrowseCursor, requestedTab: YouTubeChannelTab? = nil) throws -> YouTubeBrowsePage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MusicError.invalidURL }
        var scope: Any?
        if let contents = root["contents"] as? [String: Any] {
            if let search = contents["twoColumnSearchResultsRenderer"] as? [String: Any] { scope = search["primaryContents"] }
            else if let browse = (contents["twoColumnBrowseResultsRenderer"] ?? contents["singleColumnBrowseResultsRenderer"]) as? [String: Any],
                    let tabs = browse["tabs"] as? [[String: Any]] {
                let renderers = tabs.compactMap { $0["tabRenderer"] as? [String: Any] }
                if let requestedTab, let selected = renderers.first(where: { $0["selected"] as? Bool == true }) {
                    let title = text(selected["title"])
                    let english = requestedTab == .videos ? "Videos" : "Playlists"
                    if title != requestedTab.rawValue && title != english { return .init() }
                }
                scope = renderers.first(where: { $0["selected"] as? Bool == true })?["content"]
                    ?? (renderers.count == 1 ? renderers.first?["content"] : nil)
            }
        } else {
            scope = root["onResponseReceivedActions"] ?? root["onResponseReceivedEndpoints"] ?? root["onResponseReceivedCommands"]
        }
        guard let scope else { throw MusicError.network("YouTubeの一覧を読み込めませんでした。再試行してください。") }
        var page = YouTubeBrowsePage(), seen = Set<String>()
        func visit(_ value: Any, depth: Int) {
            guard depth < 40 else { return }
            if let list = value as? [Any] { for child in list { visit(child, depth: depth + 1) }; return }
            guard let node = value as? [String: Any] else { return }
            if node.keys.contains(where: { $0.lowercased().contains("adslot") || $0.hasPrefix("promoted") || $0 == "adPlacementRenderer" }) { return }
            if let continuation = node["continuationItemRenderer"] as? [String: Any] {
                if let token = continuationToken(continuation), context.clientVersion != nil {
                    var cursor = context
                    cursor = .init(token: token, clientVersion: cursor.clientVersion, visitorData: cursor.visitorData, apiKey: cursor.apiKey)
                    page.cursor = cursor
                }
                return
            }
            for key in ["videoRenderer", "gridVideoRenderer", "playlistVideoRenderer", "reelItemRenderer", "shortsLockupViewModel", "channelRenderer", "gridChannelRenderer", "playlistRenderer", "gridPlaylistRenderer", "lockupViewModel"] {
                if let renderer = node[key] as? [String: Any] {
                    if let item = item(renderer, renderer: key), seen.insert(item.id).inserted { page.items.append(item) }
                    return
                }
            }
            for key in node.keys.sorted() { if let child = node[key] { visit(child, depth: depth + 1) } }
        }
        visit(scope, depth: 0)
        return page
    }

    private static func continuationToken(_ value: Any) -> String? {
        if let node = value as? [String: Any] {
            if let command = node["continuationCommand"] as? [String: Any], let token = command["token"] as? String { return token }
            for key in node.keys.sorted() { if let child = node[key], let token = continuationToken(child) { return token } }
        } else if let list = value as? [Any] { for child in list { if let token = continuationToken(child) { return token } } }
        return nil
    }

    static func text(_ value: Any?) -> String {
        guard let node = value as? [String: Any] else { return value as? String ?? "" }
        return node["simpleText"] as? String ?? node["content"] as? String
            ?? (node["runs"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
    }

    static func thumbnail(_ value: Any?) -> URL? {
        if let node = value as? [String: Any] {
            if let raw = node["url"] as? String {
                let raw = raw.hasPrefix("//") ? "https:" + raw : raw
                if let url = URL(string: raw), url.scheme == "https", let host = url.host?.lowercased(),
                   ["ytimg.com", "ggpht.com", "googleusercontent.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
            for key in node.keys.sorted() { if let result = thumbnail(node[key]) { return result } }
        } else if let list = value as? [Any] { for child in list { if let result = thumbnail(child) { return result } } }
        return nil
    }

    private static func item(_ node: [String: Any], renderer: String) -> YouTubeBrowseItem? {
        var kind: YouTubeBrowseItem.Kind, id: String, title: String, subtitle: String, image: URL?, duration: Double?
        if renderer == "shortsLockupViewModel" {
            let command = (node["onTap"] as? [String: Any])?["innertubeCommand"] as? [String: Any]
            id = (command?["reelWatchEndpoint"] as? [String: Any])?["videoId"] as? String ?? ""
            let metadata = node["overlayMetadata"] as? [String: Any] ?? [:]
            title = text(metadata["primaryText"])
            subtitle = text(metadata["secondaryText"])
            kind = .video; image = thumbnail(node["thumbnail"]); duration = nil
        } else if renderer == "lockupViewModel" {
            let type = node["contentType"] as? String ?? ""
            switch type { case "LOCKUP_CONTENT_TYPE_VIDEO": kind = .video
            case "LOCKUP_CONTENT_TYPE_PLAYLIST": kind = .playlist
            case "LOCKUP_CONTENT_TYPE_CHANNEL": kind = .channel
            default: return nil }
            id = node["contentId"] as? String ?? ""
            let metadata = (node["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any] ?? [:]
            title = text(metadata["title"])
            let details = (metadata["metadata"] as? [String: Any])?["contentMetadataViewModel"] as? [String: Any]
            let rows = details?["metadataRows"] as? [[String: Any]] ?? []
            let parts = rows.flatMap { $0["metadataParts"] as? [[String: Any]] ?? [] }
            subtitle = parts.map { text($0["text"]) }.filter { !$0.isEmpty }.joined(separator: " · ")
            image = thumbnail(node["contentImage"])
            let badges = imageBadges(node["contentImage"])
            if badges.contains(where: { $0 == "LIVE" || $0.contains("ライブ") }) { return nil }
            let time = badges.first { $0.range(of: "^[0-9]+:[0-9]{2}(:[0-9]{2})?$", options: .regularExpression) != nil }
            duration = time.map { $0.split(separator: ":").compactMap { Double($0) }.reduce(0) { $0 * 60 + $1 } }
        } else {
            if renderer.lowercased().contains("channel") { kind = .channel; id = node["channelId"] as? String ?? "" }
            else if renderer == "playlistRenderer" || renderer == "gridPlaylistRenderer" { kind = .playlist; id = node["playlistId"] as? String ?? "" }
            else { kind = .video; id = node["videoId"] as? String ?? "" }
            title = text(node["title"] ?? node["headline"])
            subtitle = text(node["ownerText"] ?? node["longBylineText"] ?? node["shortBylineText"])
            if kind == .channel { subtitle = [text(node["subscriberCountText"]), text(node["videoCountText"])].filter { !$0.isEmpty }.joined(separator: " · ") }
            image = thumbnail(node["thumbnail"] ?? node["thumbnails"])
            let parts = text(node["lengthText"]).split(separator: ":").compactMap { Double($0) }
            duration = parts.isEmpty ? nil : parts.reduce(0) { $0 * 60 + $1 }
            let badges = node["badges"] as? [[String: Any]] ?? []
            if node["isPlayable"] as? Bool == false || badges.contains(where: {
                ($0["metadataBadgeRenderer"] as? [String: Any])?["style"] as? String == "BADGE_STYLE_TYPE_LIVE_NOW"
            }) { return nil }
        }
        guard YouTubeBrowseItem.validID(id, kind: kind), !title.isEmpty,
              !["Private video", "Deleted video", "非公開動画", "削除された動画"].contains(title) else { return nil }
        return .init(kind: kind, resourceID: id, title: title, subtitle: subtitle, thumbnail: image, duration: duration)
    }

    private static func imageBadges(_ value: Any?) -> [String] {
        if let node = value as? [String: Any] {
            if let badge = node["thumbnailBadgeViewModel"] as? [String: Any] { return [text(badge["text"])] }
            return node.values.flatMap { imageBadges($0) }
        }
        if let list = value as? [Any] { return list.flatMap { imageBadges($0) } }
        return []
    }
}
