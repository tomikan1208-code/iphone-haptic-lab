import Foundation
import SwiftUI

struct YouTubePage<Item: Decodable>: Decodable {
    let items: [Item]?
    let nextPageToken: String?
}

struct YouTubePlaylist: Decodable, Identifiable {
    struct Snippet: Decodable { let title: String; let description: String? }
    let id: String
    let snippet: Snippet
}

struct YouTubePlaylistItem: Decodable {
    struct Snippet: Decodable {
        struct Resource: Decodable { let videoId: String? }
        let title: String
        let videoOwnerChannelTitle: String?
        let resourceId: Resource
    }
    let id: String
    let snippet: Snippet?
    var videoID: String? { snippet?.resourceId.videoId }
    var selection: MusicSelection? {
        guard let snippet, let id = videoID,
              !["Private video", "Deleted video"].contains(snippet.title) else { return nil }
        return try? MusicSelection.youtube(id: id, title: snippet.title, artist: snippet.videoOwnerChannelTitle ?? "")
    }
}

private struct YouTubeChannel: Decodable {
    struct Snippet: Decodable { let title: String }
    struct Details: Decodable {
        struct Related: Decodable { let likes: String? }
        let relatedPlaylists: Related
    }
    let id: String
    let snippet: Snippet
    let contentDetails: Details?
}

private struct YouTubeManagedList: Codable {
    var playlistID: String?
    var members: [String: String] = [:]
}

@MainActor
final class YouTubeAccount: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var accountTitle = ""
    @Published private(set) var playlists: [YouTubePlaylist] = []
    @Published private(set) var playlistVideos: [MusicSelection] = []
    @Published private(set) var selectedPlaylist: YouTubePlaylist?
    @Published private(set) var loading = false
    @Published private(set) var authorizing = false
    @Published private(set) var autoSync = false
    @Published private(set) var syncing = false
    @Published private(set) var syncStatus = "作成済みの曲はアプリ内リストに保存されます"
    @Published var message: String?
    @Published private(set) var nextPlaylistPage: String?
    @Published private(set) var nextVideoPage: String?
    let oauth = GoogleOAuth()
    private let defaults: UserDefaults
    private var desiredIDs: Set<String> = []
    private var desiredRevision = 0
    private var syncTask: Task<Void, Never>?
    private var syncID: UUID?
    private var loadRevision = 0
    private var authorizationGeneration = 0
    var configured: Bool { oauth.isConfigured }
    var managedPlaylistURL: URL? {
        guard let id = managedList.playlistID else { return nil }
        var components = URLComponents(string: "https://www.youtube.com/playlist")!
        components.queryItems = [.init(name: "list", value: id)]
        return components.url
    }
    private var accountKey: String? {
        guard let credential = oauth.credential, !credential.channelID.isEmpty else { return nil }
        return "youtube.\(credential.clientID).\(credential.channelID)"
    }
    private var managedList: YouTubeManagedList {
        guard let key = accountKey, let data = defaults.data(forKey: key + ".managed") else { return YouTubeManagedList() }
        return (try? JSONDecoder().decode(YouTubeManagedList.self, from: data)) ?? YouTubeManagedList()
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        restoreAccount()
    }

    func signIn() async {
        guard !authorizing else { return }
        authorizing = true
        defer { authorizing = false }
        do {
            try await authorize(write: false)
            await loadPlaylists()
        } catch { handle(error) }
    }

    func enableSync(records: [MusicRecord]) async {
        guard !authorizing else { return }
        authorizing = true
        defer { authorizing = false }
        do {
            if oauth.credential?.canWrite != true { try await authorize(write: true) }
            guard let key = accountKey else { throw MusicError.account("YouTubeのチャンネルを確認できませんでした。") }
            defaults.set(true, forKey: key + ".autoSync")
            autoSync = true
            synchronize(records: records, force: true)
        } catch { handle(error) }
    }

    func disableSync() {
        if let key = accountKey { defaults.set(false, forKey: key + ".autoSync") }
        autoSync = false
        syncTask?.cancel()
        syncTask = nil
        syncID = nil
        syncing = false
        syncStatus = "作成済みの曲はアプリ内リストに保存されます"
    }

    func disconnect() {
        authorizationGeneration += 1
        loadRevision += 1
        disableSync()
        oauth.disconnect()
        connected = false
        accountTitle = ""
        playlists = []
        playlistVideos = []
        selectedPlaylist = nil
        nextPlaylistPage = nil
        nextVideoPage = nil
        loading = false
        message = nil
    }

    func loadPlaylists(more: Bool = false) async {
        guard connected, !loading, !more || nextPlaylistPage != nil else { return }
        loading = true
        let revision = loadRevision
        defer { if loadRevision == revision { loading = false } }
        do {
            var query = ["part": "snippet", "mine": "true", "maxResults": "50"]
            if more { query["pageToken"] = nextPlaylistPage }
            let page: YouTubePage<YouTubePlaylist> = try await request("playlists", query: query)
            guard loadRevision == revision else { return }
            playlists = more ? playlists + (page.items ?? []) : page.items ?? []
            nextPlaylistPage = page.nextPageToken
            message = nil
        } catch { if loadRevision == revision { handle(error) } }
    }

    func loadVideos(_ playlist: YouTubePlaylist, more: Bool = false) async {
        guard connected, !loading, !more || nextVideoPage != nil else { return }
        loading = true
        loadRevision += 1
        let revision = loadRevision
        if !more { selectedPlaylist = playlist; playlistVideos = []; nextVideoPage = nil }
        defer { if loadRevision == revision { loading = false } }
        do {
            var query = ["part": "snippet", "playlistId": playlist.id, "maxResults": "50"]
            if more { query["pageToken"] = nextVideoPage }
            let page: YouTubePage<YouTubePlaylistItem> = try await request("playlistItems", query: query)
            guard loadRevision == revision else { return }
            let videos = (page.items ?? []).compactMap(\.selection)
            var unique = Set(playlistVideos.map(\.id))
            playlistVideos.append(contentsOf: videos.filter { unique.insert($0.id).inserted })
            nextVideoPage = page.nextPageToken
            message = nil
        } catch { if loadRevision == revision { handle(error) } }
    }

    func closePlaylist() { loadRevision += 1; loading = false; selectedPlaylist = nil; playlistVideos = [] }

    func synchronize(records: [MusicRecord], force: Bool = false) {
        let ids = Set(records.filter(\.isPrepared).compactMap { $0.selection.videoID })
        let changed = ids != desiredIDs
        desiredIDs = ids
        if changed { desiredRevision += 1 }
        guard connected, autoSync, oauth.credential?.canWrite == true, let key = accountKey,
              syncTask == nil, changed || force else { return }
        let id = UUID()
        syncID = id
        syncing = true
        syncStatus = "YouTubeの作成済みリストを更新中"
        syncTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.syncID == id { self.syncing = false; self.syncTask = nil; self.syncID = nil }
            }
            do {
                while self.syncID == id, self.accountKey == key {
                    let revision = self.desiredRevision
                    try await self.syncList(key: key)
                    try Task.checkCancellation()
                    if self.syncID != id { return }
                    if revision == self.desiredRevision { break }
                }
                guard self.syncID == id else { return }
                self.syncStatus = "YouTubeの「触感ラボ・振動作成済み」と同期済み"
            } catch {
                guard self.syncID == id, !(error is CancellationError) else { return }
                self.syncStatus = "アプリに保存済み。YouTubeへの同期は再試行できます。"
                self.message = error.localizedDescription
            }
        }
    }

    private func syncList(key: String) async throws {
        var state = managedList
        if let id = state.playlistID {
            let page: YouTubePage<YouTubePlaylist> = try await request("playlists", query: ["part": "snippet", "id": id])
            if page.items?.isEmpty != false { state = YouTubeManagedList() }
        }
        if state.playlistID == nil {
            // Find our marked list before creating it, including after a lost create response.
            var pageToken: String?
            repeat {
                var query = ["part": "snippet", "mine": "true", "maxResults": "50"]
                query["pageToken"] = pageToken
                let page: YouTubePage<YouTubePlaylist> = try await request("playlists", query: query)
                if let found = page.items?.first(where: { $0.snippet.title == "触感ラボ・振動作成済み" &&
                    $0.snippet.description == "触感ラボで振動を作成した動画。アプリの自動同期で管理します。" }) {
                    state.playlistID = found.id
                    break
                }
                pageToken = page.nextPageToken
            } while pageToken != nil
        }
        if state.playlistID == nil {
            let created: YouTubePlaylist = try await request("playlists", method: "POST", query: ["part": "snippet,status"], body: [
                "snippet": ["title": "触感ラボ・振動作成済み", "description": "触感ラボで振動を作成した動画。アプリの自動同期で管理します。"],
                "status": ["privacyStatus": "private"]
            ])
            state.playlistID = created.id
        }
        try saveManaged(state, key: key)
        guard let playlistID = state.playlistID else { return }
        // Reconcile the dedicated list after reinstalls, remote deletions, or lost POST responses.
        var remoteMembers: [String: String] = [:]
        var duplicateItems: [String] = []
        var itemPage: String?
        repeat {
            var query = ["part": "snippet", "playlistId": playlistID, "maxResults": "50"]
            query["pageToken"] = itemPage
            let page: YouTubePage<YouTubePlaylistItem> = try await request("playlistItems", query: query)
            for item in page.items ?? [] {
                guard let videoID = item.videoID else { continue }
                if remoteMembers[videoID] != nil {
                    duplicateItems.append(item.id)
                } else { remoteMembers[videoID] = item.id }
            }
            itemPage = page.nextPageToken
        } while itemPage != nil
        for id in duplicateItems {
            do { _ = try await requestData("playlistItems", method: "DELETE", query: ["id": id]) }
            catch let error as YouTubeHTTPError where error.status == 404 { /* Already removed. */ }
        }
        state.members = remoteMembers
        try saveManaged(state, key: key)
        for (videoID, itemID) in state.members where !desiredIDs.contains(videoID) {
            do { _ = try await requestData("playlistItems", method: "DELETE", query: ["id": itemID]) }
            catch let error as YouTubeHTTPError where error.status == 404 { /* Already removed on YouTube. */ }
            state.members[videoID] = nil
            try saveManaged(state, key: key)
        }
        for videoID in desiredIDs.sorted() where state.members[videoID] == nil {
            try Task.checkCancellation()
            guard desiredIDs.contains(videoID), accountKey == key else { continue }
            // Checking before insertion also recovers a successful POST whose response was lost.
            let existing: YouTubePage<YouTubePlaylistItem> = try await request("playlistItems", query: [
                "part": "id,snippet", "playlistId": playlistID, "videoId": videoID, "maxResults": "50"
            ])
            let item: YouTubePlaylistItem
            if let found = existing.items?.first { item = found }
            else {
                guard desiredIDs.contains(videoID) else { continue }
                item = try await request("playlistItems", method: "POST", query: ["part": "snippet"], body: [
                    "snippet": ["playlistId": playlistID, "resourceId": ["kind": "youtube#video", "videoId": videoID]]
                ])
            }
            state.members[videoID] = item.id
            try saveManaged(state, key: key)
        }
    }

    private func saveManaged(_ state: YouTubeManagedList, key: String) throws {
        try Task.checkCancellation()
        guard accountKey == key else { throw CancellationError() }
        defaults.set(try JSONEncoder().encode(state), forKey: key + ".managed")
    }

    private func authorize(write: Bool) async throws {
        let generation = authorizationGeneration
        let previous = oauth.credential
        var credential = try await oauth.authorize(write: write)
        let page: YouTubePage<YouTubeChannel> = try await request("channels",
            query: ["part": "snippet,contentDetails", "mine": "true"], token: credential.accessToken)
        guard generation == authorizationGeneration else { throw CancellationError() }
        guard let channel = page.items?.first else { throw MusicError.account("このGoogleアカウントにYouTubeのチャンネルがありません。YouTubeでチャンネルを作成してからログインしてください。") }
        if write, !credential.canWrite { throw MusicError.account("再生リストへの追加権限が許可されませんでした。アプリ内リストを利用できます。") }
        credential.channelID = channel.id
        credential.channelTitle = channel.snippet.title
        if credential.refreshToken.isEmpty, previous?.channelID == channel.id {
            credential.refreshToken = previous?.refreshToken ?? ""
        }
        syncTask?.cancel()
        syncID = nil
        syncTask = nil
        syncing = false
        loadRevision += 1
        loading = false
        playlists = []
        selectedPlaylist = nil
        playlistVideos = []
        try oauth.save(credential)
        restoreAccount()
    }

    private func restoreAccount() {
        connected = oauth.credential?.channelID.isEmpty == false
        accountTitle = oauth.credential?.channelTitle ?? ""
        if let key = accountKey { autoSync = defaults.bool(forKey: key + ".autoSync") && oauth.credential?.canWrite == true }
    }

    private func handle(_ error: Error) {
        if (error as NSError).domain == "com.apple.AuthenticationServices.WebAuthenticationSession", (error as NSError).code == 1 { return }
        if !(error is CancellationError) { message = error.localizedDescription }
    }

    private func request<T: Decodable>(_ endpoint: String, method: String = "GET", query: [String: String],
                                       body: [String: Any]? = nil, token: String? = nil) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await requestData(endpoint, method: method, query: query, body: body, token: token))
    }

    private func requestData(_ endpoint: String, method: String = "GET", query: [String: String],
                             body: [String: Any]? = nil, token: String? = nil) async throws -> Data {
        try Task.checkCancellation()
        let accessToken: String
        if let token { accessToken = token } else { accessToken = try await oauth.accessToken() }
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/\(endpoint)")!
        components.queryItems = query.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw MusicError.network("YouTubeから応答がありませんでした。") }
        guard (200..<300).contains(http.statusCode) else { throw YouTubeHTTPError(status: http.statusCode) }
        return data
    }

    static func metadata(for selection: MusicSelection) async throws -> MusicSelection {
        guard selection.kind == .youtube else { return selection }
        var url = URLComponents(string: "https://www.youtube.com/oembed")!
        url.queryItems = [.init(name: "url", value: selection.url), .init(name: "format", value: "json")]
        let (data, response) = try await URLSession.shared.data(from: url.url!)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw MusicError.network("動画の情報を取得できません。公開されている動画のURLか確認してください。")
        }
        struct Metadata: Decodable { let title: String; let author_name: String }
        let metadata = try JSONDecoder().decode(Metadata.self, from: data)
        var enriched = selection
        enriched.title = metadata.title
        enriched.artist = metadata.author_name
        return enriched
    }
}

private struct YouTubeHTTPError: LocalizedError {
    let status: Int
    var errorDescription: String? {
        switch status {
        case 401: return "Googleのログインが無効になっています。もう一度ログインしてください。"
        case 403: return "YouTubeのアクセス権またはAPI利用枠を確認してください。アプリ内リストは引き続き使えます。"
        case 404: return "YouTubeの再生リストが見つかりませんでした。"
        default: return "YouTubeへの接続に失敗しました（\(status)）。後でもう一度試してください。"
        }
    }
}
