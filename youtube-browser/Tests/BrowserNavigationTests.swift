import XCTest
@testable import ResonWeb

final class BrowserNavigationTests: XCTestCase {
    func testSearchRetainsJapaneseAndEncodesURLSeparatorsAsQueryText() {
        let url = BrowserNavigation.destination(for: "  宇多田ヒカル & live #2026  ")
        XCTAssertEqual(url.host, "www.youtube.com")
        XCTAssertEqual(url.path, "/results")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                       [URLQueryItem(name: "search_query", value: "宇多田ヒカル & live #2026")])
    }
    func testDirectYouTubeURLsAndSiteHistoryUseTheWebsite() {
        XCTAssertEqual(BrowserNavigation.destination(for: "https://youtu.be/lkiV3U0GfGg").absoluteString, "https://youtu.be/lkiV3U0GfGg")
        XCTAssertEqual(BrowserNavigation.destination(for: "youtube.com/watch?v=lkiV3U0GfGg").host, "youtube.com")
        XCTAssertEqual(BrowserPage.history.url.path, "/feed/history")
        XCTAssertEqual(BrowserPage.playlists.url.path, "/feed/playlists")
    }
    func testLookalikeDomainsCredentialsAndNonHTTPSCannotBecomeInternalPages() {
        for input in ["https://youtube.com.example.org/watch", "https://user:secret@youtube.com", "http://youtube.com", "javascript:alert(1)"] {
            let url = URL(string: input)!
            XCTAssertFalse(BrowserNavigation.isInternal(url))
            XCTAssertEqual(BrowserNavigation.destination(for: input).path, "/results")
        }
        XCTAssertTrue(BrowserNavigation.isInternal(URL(string: "https://accounts.google.com/")!))
    }
}
