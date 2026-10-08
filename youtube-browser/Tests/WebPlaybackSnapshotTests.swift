import XCTest
@testable import ResonWeb

final class WebPlaybackSnapshotTests: XCTestCase {
    let now = 1_800_000_000.0
    let page = URL(string: "https://www.youtube.com/watch?v=lkiV3U0GfGg")!
    func body(_ changes: [String: Any] = [:]) -> [String: Any] {
        var values: [String: Any] = ["url": page.absoluteString, "videoID": "lkiV3U0GfGg", "title": "曲", "artist": "演奏者",
            "position": 20.0, "duration": 60.0, "rate": 1.0, "sent": now * 1_000,
            "paused": false, "ended": false, "seeking": false, "ready": true, "buffering": false, "advertisement": false, "hidden": false]
        values.merge(changes) { _, new in new }
        return values
    }
    func testWatchAndShortsIdentityAndMediaState() throws {
        let snapshot = try XCTUnwrap(WebPlaybackSnapshot.decode(body(), pageURL: page, now: now))
        XCTAssertTrue(snapshot.playing)
        XCTAssertEqual(snapshot.selection?.id, "youtube-lkiV3U0GfGg")
        XCTAssertEqual(snapshot.selection?.duration, 60)
        let shorts = URL(string: "https://www.youtube.com/shorts/lkiV3U0GfGg")!
        XCTAssertNotNil(WebPlaybackSnapshot.decode(body(["url": shorts.absoluteString]), pageURL: shorts, now: now))
    }
    func testPausedEndedSeekingBufferingAdvertisementsAndHiddenCannotPlay() throws {
        for flag in ["paused", "ended", "seeking", "buffering", "advertisement", "hidden"] {
            let snapshot = try XCTUnwrap(WebPlaybackSnapshot.decode(body([flag: true]), pageURL: page, now: now))
            XCTAssertFalse(snapshot.playing, flag)
        }
        XCTAssertNil(WebPlaybackSnapshot.decode(body(["advertisement": true]), pageURL: page, now: now)?.selection?.duration)
    }
    func testRejectsStaleFutureNonFiniteAndOutOfRangeSamples() {
        let cases: [[String: Any]] = [["sent": (now - 0.351) * 1_000], ["sent": (now + 0.101) * 1_000],
            ["position": Double.nan], ["duration": Double.infinity], ["position": -1], ["duration": -1],
            ["position": 62], ["duration": 0], ["rate": 0], ["rate": 2.1], ["ready": 1], ["position": true]]
        for changes in cases {
            XCTAssertNil(WebPlaybackSnapshot.decode(body(changes), pageURL: page, now: now))
        }
    }
    func testRejectsOldVideoLookalikeCredentialsAndAuthenticationPage() {
        let cases: [[String: Any]] = [["videoID": "dQw4w9WgXcQ"], ["videoID": ""],
            ["url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ"],
            ["url": "https://youtube.com.example.org/watch?v=lkiV3U0GfGg"],
            ["url": "https://user:pass@www.youtube.com/watch?v=lkiV3U0GfGg"],
            ["url": "https://accounts.google.com/watch?v=lkiV3U0GfGg"]]
        for changes in cases {
            XCTAssertNil(WebPlaybackSnapshot.decode(body(changes), pageURL: page, now: now))
        }
        XCTAssertNil(WebPlaybackSnapshot.decode(body(), pageURL: URL(string: "https://accounts.google.com/")!, now: now))
    }
    func testOnlyYouTubeHTTPSMainFramesAreTrusted() {
        XCTAssertTrue(WebPlaybackSnapshot.acceptsOrigin(scheme: "https", host: "www.youtube.com", mainFrame: true))
        for host in ["accounts.google.com", "www.youtube.com.evil.org", "youtu.be", ""] {
            XCTAssertFalse(WebPlaybackSnapshot.acceptsOrigin(scheme: "https", host: host, mainFrame: true))
        }
        XCTAssertFalse(WebPlaybackSnapshot.acceptsOrigin(scheme: "http", host: "www.youtube.com", mainFrame: true))
        XCTAssertFalse(WebPlaybackSnapshot.acceptsOrigin(scheme: "https", host: "www.youtube.com", mainFrame: false))
    }
    func testFeedHasNoVideoAndNoPreparationSelection() throws {
        let feed = URL(string: "https://www.youtube.com/feed/history")!
        let snapshot = try XCTUnwrap(WebPlaybackSnapshot.decode(body(["url": feed.absoluteString, "videoID": "", "ready": false,
            "duration": 0.0, "position": 0.0, "paused": true]), pageURL: feed, now: now))
        XCTAssertNil(snapshot.selection)
        XCTAssertFalse(snapshot.playing)
    }
}
