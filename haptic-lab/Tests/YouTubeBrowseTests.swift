import XCTest
@testable import HapticLab

final class YouTubeBrowseTests: XCTestCase {
    func testSearchIncludesChannelsPlaylistsAndVideosInOriginalOrder() throws {
        let channel: [String: Any] = ["channelId": "UC8T8_deSUS97DWZeKO_TL9Q", "title": ["simpleText": "NHK MUSIC"]]
        let playlist: [String: Any] = ["playlistId": "PL-TestPlaylist", "title": ["runs": [["text": "音楽のリスト"]]]]
        let video: [String: Any] = ["videoId": "lkiV3U0GfGg", "title": ["simpleText": "動画"], "lengthText": ["simpleText": "9:07"]]
        let content: [[String: Any]] = [["channelRenderer": channel], ["playlistRenderer": playlist], ["videoRenderer": video], ["videoRenderer": video], ["adSlotRenderer": ["videoRenderer": video]]]
        let html = try html(["contents": ["twoColumnSearchResultsRenderer": ["primaryContents": ["sectionListRenderer": ["contents": content]]]]])
        let page = try YouTubeBrowseService.parse(html)
        XCTAssertEqual(page.items.map(\.kind), [.channel, .playlist, .video])
        XCTAssertEqual(page.items.last?.selection?.duration, 547)
        XCTAssertNil(page.items.first?.selection)
    }

    func testChannelUsesOnlySelectedTabAndParsesModernVideoAndPagination() throws {
        let modern: [String: Any] = ["contentId": "lkiV3U0GfGg", "contentType": "LOCKUP_CONTENT_TYPE_VIDEO",
            "metadata": ["lockupMetadataViewModel": ["title": ["content": "動画"]]],
            "contentImage": ["thumbnailViewModel": ["overlays": [["thumbnailBadgeViewModel": ["text": "9:07"]]]]]]
        let continuation: [String: Any] = ["continuationItemRenderer": ["continuationEndpoint": ["continuationCommand": ["token": "next-page"]]]]
        let tabs: [[String: Any]] = [
            ["tabRenderer": ["title": "ホーム", "content": ["videoRenderer": ["videoId": "dQw4w9WgXcQ", "title": ["simpleText": "無関係な動画"]]]]],
            ["tabRenderer": ["title": "動画", "selected": true, "content": ["richGridRenderer": ["contents": [["richItemRenderer": ["content": ["lockupViewModel": modern]]], continuation]]]]]
        ]
        let page = try YouTubeBrowseService.parse(html(["contents": ["twoColumnBrowseResultsRenderer": ["tabs": tabs]]]))
        XCTAssertEqual(page.items.map(\.resourceID), ["lkiV3U0GfGg"])
        XCTAssertEqual(page.items.first?.duration, 547)
        XCTAssertEqual(page.cursor?.token, "next-page")
        XCTAssertEqual(page.cursor?.clientVersion, "test-version")
        let next = try JSONSerialization.data(withJSONObject: ["onResponseReceivedActions": [["appendContinuationItemsAction": ["continuationItems": [["lockupViewModel": modern]]]]]])
        XCTAssertEqual(try YouTubeBrowseService.parseJSON(next, context: XCTUnwrap(page.cursor)).items, page.items)
    }

    func testModernPlaylistAndUnavailableItemsDoNotBecomePlayableVideos() throws {
        let playlist: [String: Any] = ["contentId": "PL-TestPlaylist", "contentType": "LOCKUP_CONTENT_TYPE_PLAYLIST", "metadata": ["lockupMetadataViewModel": ["title": ["content": "再生リスト"]]]]
        let contents: [[String: Any]] = [["lockupViewModel": playlist], ["playlistVideoRenderer": ["videoId": "dQw4w9WgXcQ", "isPlayable": false, "title": ["simpleText": "Private video"]]]]
        let page = try YouTubeBrowseService.parse(html(["contents": ["twoColumnSearchResultsRenderer": ["primaryContents": ["contents": contents]]]]))
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].kind, .playlist)
        XCTAssertNil(page.items[0].selection)
        XCTAssertFalse(YouTubeBrowseItem.validID("UC../../evil", kind: .channel))
        XCTAssertNil(YouTubeBrowseService.thumbnail(["url": "https://evil.example/image.png"]))
    }

    func testAuthenticatedSearchDecodesAllThreeResourceKinds() throws {
        for (key, id, kind) in [("videoId", "lkiV3U0GfGg", YouTubeBrowseItem.Kind.video),
                                ("channelId", "UC8T8_deSUS97DWZeKO_TL9Q", .channel), ("playlistId", "PL-TestPlaylist", .playlist)] {
            let data = try JSONSerialization.data(withJSONObject: ["id": [key: id], "snippet": ["title": "結果", "channelTitle": "作成者"]])
            let item = try JSONDecoder().decode(YouTubeSearchItem.self, from: data)
            XCTAssertEqual(item.browseItem?.kind, kind)
            XCTAssertEqual(item.browseItem?.resourceID, id)
        }
    }

    func testShortsInPlaylistsAreVideosAndMissingChannelTabsStayEmpty() throws {
        let short: [String: Any] = ["onTap": ["innertubeCommand": ["reelWatchEndpoint": ["videoId": "lkiV3U0GfGg"]]],
                                   "overlayMetadata": ["primaryText": ["content": "Shorts"]]]
        let content: [String: Any] = ["richGridRenderer": ["contents": [["shortsLockupViewModel": short]]]]
        let selected: [String: Any] = ["tabRenderer": ["selected": true, "title": "再生リスト", "content": content]]
        let response = try html(["contents": ["twoColumnBrowseResultsRenderer": ["tabs": [selected]]]])
        let page = try YouTubeBrowseService.parse(response)
        XCTAssertEqual(page.items.first?.selection?.videoID, "lkiV3U0GfGg")
        XCTAssertTrue(try YouTubeBrowseService.parse(response, requestedTab: .videos).items.isEmpty)
    }

    @MainActor
    func testNavigationRestoresSearchAndParentChannelWithoutLoadingAgain() async throws {
        let channel = YouTubeBrowseItem(kind: .channel, resourceID: "UC8T8_deSUS97DWZeKO_TL9Q", title: "チャンネル")
        let playlist = YouTubeBrowseItem(kind: .playlist, resourceID: "PL-TestPlaylist", title: "再生リスト")
        let video = YouTubeBrowseItem(kind: .video, resourceID: "lkiV3U0GfGg", title: "動画")
        let browser = YouTubeSearch(loader: { target, _ in
            switch target {
            case .search: return .init(items: [channel, video])
            case .channel(_, .videos): return .init(items: [video])
            case .channel(_, .playlists): return .init(items: [playlist])
            case .playlist: return .init(items: [video])
            }
        })
        let account = YouTubeAccount()
        browser.query = "音楽"
        browser.submit(account: account)
        try await wait(browser)
        browser.open(channel, account: account)
        try await wait(browser)
        browser.channelTab(.playlists, account: account)
        try await wait(browser)
        browser.open(playlist, account: account)
        try await wait(browser)
        browser.back()
        XCTAssertEqual(browser.results, [playlist])
        browser.back()
        XCTAssertEqual(browser.results, [channel, video])
        XCTAssertFalse(browser.canGoBack)
    }

    @MainActor private func wait(_ browser: YouTubeSearch) async throws {
        for _ in 0..<100 where browser.searching { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(browser.searching)
        XCTAssertNil(browser.message)
    }

    private func html(_ root: [String: Any]) throws -> String {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
        return "<script>ytcfg.set({\"INNERTUBE_CLIENT_VERSION\":\"test-version\"});var ytInitialData = \(json);</script>"
    }
}
