import XCTest
import WebKit
@testable import HapticLab

final class YouTubePlayerControlsTests: XCTestCase {
    @MainActor
    func testRealWebKitStylesRestoreControlsAndRejectUntrustedMessagesWithoutReloading() async throws {
        let origin = "https://com.tomikan1208.hapticlab"
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(YouTubePlayerControls.script(origin: origin))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 667, height: 375), configuration: configuration)
        let loaded = expectation(description: "Control document loaded")
        let delegate = ControlDocumentDelegate { loaded.fulfill() }
        webView.navigationDelegate = delegate
        webView.loadHTMLString("""
            <html><head></head><body><div class="ytp-chrome-bottom">seek and settings</div>
            <script>window.savedClock=42;window.instance='same-player';</script></body></html>
            """, baseURL: URL(string: "https://www.youtube.com/embed/lkiV3U0GfGg"))
        await fulfillment(of: [loaded], timeout: 10)
        let visibility = "getComputedStyle(document.querySelector('.ytp-chrome-bottom')).visibility"
        var actual = try await webView.evaluateJavaScript(visibility) as? String
        XCTAssertEqual(actual, "hidden")
        for message in [
            "{data:{type:'reson-player-controls',visible:true},origin:'https://youtube.com.example.org',source:window}",
            "{data:{type:'reson-player-controls',visible:'true'},origin:'\(origin)',source:window}",
            "{data:{type:'reson-player-controls',visible:true},origin:'\(origin)',source:null}"
        ] {
            _ = try await webView.evaluateJavaScript("window.dispatchEvent(new MessageEvent('message',\(message)))")
            actual = try await webView.evaluateJavaScript(visibility) as? String
            XCTAssertEqual(actual, "hidden")
        }
        _ = try await webView.evaluateJavaScript("""
            window.dispatchEvent(new MessageEvent('message', {
              data:{type:'reson-player-controls',visible:true},origin:'\(origin)',source:window
            }));
            """)
        actual = try await webView.evaluateJavaScript(visibility) as? String
        XCTAssertEqual(actual, "visible")
        let clock = try await webView.evaluateJavaScript("window.savedClock") as? Int
        let instance = try await webView.evaluateJavaScript("window.instance") as? String
        XCTAssertEqual(clock, 42)
        XCTAssertEqual(instance, "same-player")
        _ = try await webView.evaluateJavaScript("""
            window.dispatchEvent(new MessageEvent('message', {
              data:{type:'reson-player-controls',visible:false},origin:'\(origin)',source:window
            }));
            """)
        actual = try await webView.evaluateJavaScript(visibility) as? String
        XCTAssertEqual(actual, "hidden")
        withExtendedLifetime(delegate) {}
    }
}

private final class ControlDocumentDelegate: NSObject, WKNavigationDelegate {
    let ready: () -> Void
    init(ready: @escaping () -> Void) { self.ready = ready }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready() }
}
