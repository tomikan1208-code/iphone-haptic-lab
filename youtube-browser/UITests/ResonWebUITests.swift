import XCTest

final class ResonWebUITests: XCTestCase {
    func testNativeChromeAndWebsiteTabsAndLandscape() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--browser-ui-fixture"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let title = app.staticTexts["Reson Web"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let input = app.textFields["browser.searchQuery"]
        XCTAssertTrue(input.isHittable)
        XCTAssertGreaterThan(input.frame.minY, title.frame.maxY)
        XCTAssertGreaterThan(app.buttons["browser.account"].frame.minX, app.buttons["browser.menu"].frame.maxX)
        XCTAssertTrue(app.webViews["browser.website"].waitForExistence(timeout: 10))
        screenshot("00-reson-web-search", app)
        input.tap()
        input.typeText("Piano live\n")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["browser.tab.history"].tap()
        XCTAssertTrue(app.buttons["browser.tab.history"].isSelected)
        XCTAssertTrue(app.webViews.staticTexts["視聴履歴"].waitForExistence(timeout: 10))
        XCTAssertFalse(input.exists)
        screenshot("01-reson-web-history", app)
        app.buttons["browser.tab.playlists"].tap()
        XCTAssertTrue(app.webViews.staticTexts["あなたの再生リスト"].waitForExistence(timeout: 10))
        screenshot("02-reson-web-playlists", app)
        app.buttons["browser.menu"].tap()
        app.buttons["browser.hideChrome"].tap()
        XCTAssertTrue(app.buttons["browser.restoreChrome"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["browser.tab.history"].exists)
        XCUIDevice.shared.orientation = .landscapeRight
        expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        screenshot("03-reson-web-landscape", app)
        app.buttons["browser.restoreChrome"].tap()
        XCTAssertTrue(app.buttons["browser.tab.history"].exists)
    }
    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
