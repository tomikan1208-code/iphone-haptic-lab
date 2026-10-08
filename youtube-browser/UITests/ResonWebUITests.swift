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
        if !app.buttons["browser.hideChrome"].isHittable { app.swipeUp() }
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

    func testWebsiteClockPreparationAdjustmentsAdsAndSavedTrackSurviveRelaunch() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--browser-ui-fixture", "--browser-haptics-fixture", "--reset-browser-haptics-fixture",
                               "--browser-watch-fixture", "--music-test-library", "--reset-music-test-library"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.webViews.staticTexts["テスト動画"].waitForExistence(timeout: 10))
        let preparationExists = app.buttons["browser.haptics.prepare"].waitForExistence(timeout: 10)
        let diagnostic = app.staticTexts["browser.haptics.diagnostic"].label
        XCTAssertTrue(preparationExists, diagnostic)
        XCTAssertFalse(app.staticTexts["music.firstPreparation"].exists)
        screenshot("04-reson-web-haptics-before-preparation", app)
        app.buttons["browser.haptics.prepare"].tap()
        XCTAssertTrue(app.staticTexts["music.firstPreparation"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !app.buttons["music.prepare"].isHittable { app.swipeUp() }
        app.buttons["music.prepare"].tap()
        XCTAssertTrue(app.buttons["browser.haptics.adjust"].waitForExistence(timeout: 15))
        app.buttons["動画を再生"].tap()
        waitForClock(app, greaterThan: 0.3)
        app.buttons["browser.haptics.adjust"].tap()
        XCTAssertTrue(app.buttons["browser.haptics.crispPreset"].waitForExistence(timeout: 5))
        app.buttons["browser.haptics.crispPreset"].tap()
        XCTAssertEqual(app.sliders["browser.haptics.continuous"].value as? String, "25%")
        XCTAssertEqual(app.sliders["browser.haptics.transient"].value as? String, "100%")
        screenshot("05-reson-web-independent-haptic-adjustments", app)
        app.buttons["browser.haptics.closeSettings"].tap()
        let before = clock(app)
        waitForClock(app, greaterThan: before + 0.2)
        app.buttons["一時停止"].tap()
        waitForStatus(app, contains: "一時停止")
        let paused = clock(app)
        expectation(for: NSPredicate { _, _ in abs(self.clock(app) - paused) < 0.15 }, evaluatedWith: app)
        waitForExpectations(timeout: 3)
        app.buttons["動画を再生"].tap()
        waitForClock(app, greaterThan: paused + 0.2)
        app.buttons["20秒へ移動"].tap()
        waitForClock(app, greaterThan: 19.9)
        tapWebsiteButton("広告を切り替え", app)
        waitForStatus(app, contains: "広告中")
        screenshot("06-reson-web-advertisement-waits", app)
        tapWebsiteButton("広告を切り替え", app)
        app.buttons["browser.haptics.toggle"].tap()
        waitForStatus(app, contains: "振動オフ")
        let whileDisabled = clock(app)
        waitForClock(app, greaterThan: whileDisabled + 0.2)
        app.buttons["browser.haptics.toggle"].tap()
        if !app.links["次の動画"].isHittable { app.webViews["browser.website"].swipeUp() }
        app.links["次の動画"].tap()
        XCTAssertTrue(app.buttons["browser.haptics.prepare"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["browser.haptics.adjust"].exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-browser-haptics-fixture" || $0 == "--reset-music-test-library" || $0 == "--browser-watch-fixture" }
        app.launch()
        XCTAssertTrue(app.buttons["browser.menu"].waitForExistence(timeout: 10))
        app.buttons["browser.menu"].tap()
        app.buttons["browser.haptics.saved"].tap()
        XCTAssertTrue(app.buttons["browser.saved.lkiV3U0GfGg"].waitForExistence(timeout: 5))
        screenshot("07-reson-web-saved-haptics", app)
        app.buttons["browser.saved.lkiV3U0GfGg"].tap()
        XCTAssertTrue(app.buttons["browser.haptics.adjust"].waitForExistence(timeout: 10))
        app.buttons["browser.haptics.adjust"].tap()
        XCTAssertTrue(app.staticTexts["browser.haptics.settingsScope"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["browser.haptics.settingsScope"].label, "この動画の個別設定")
        XCTAssertEqual(app.sliders["browser.haptics.continuous"].value as? String, "25%")
    }

    func testWebsitePlaybackRemainsInteractiveAfterNativeSearchDismissesKeyboard() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--browser-ui-fixture", "--browser-haptics-fixture", "--reset-browser-haptics-fixture"]
        app.launch()
        defer { app.terminate() }
        let input = app.textFields["browser.searchQuery"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("https://www.youtube.com/watch?v=lkiV3U0GfGg\n")
        XCTAssertTrue(app.buttons["browser.haptics.prepare"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.buttons["動画を再生"].tap()
        waitForClock(app, greaterThan: 0.3)
        app.buttons["一時停止"].tap()
        XCTAssertEqual(app.state, .runningForeground)
        screenshot("08-reson-web-playback-after-native-search", app)
    }

    func testWebsiteTouchWithoutPlaybackObserver() {
        checkWebsiteTouch(extraArgument: "--browser-without-observer-fixture")
    }

    func testWebsiteTouchWithObserverAndWithoutHapticBar() {
        checkWebsiteTouch(extraArgument: "--browser-without-haptic-bar-fixture")
    }

    private func checkWebsiteTouch(extraArgument: String) {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--browser-ui-fixture", "--browser-haptics-fixture", "--browser-watch-fixture",
                               "--reset-browser-haptics-fixture", extraArgument]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.webViews.staticTexts["テスト動画"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["browser.haptics.prepare"].exists)
        app.buttons["動画を再生"].tap()
        XCTAssertEqual(app.state, .runningForeground)
        app.buttons["一時停止"].tap()
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func clock(_ app: XCUIApplication) -> Double {
        Double(app.staticTexts["browser.haptics.clock"].label) ?? -1
    }
    private func tapWebsiteButton(_ title: String, _ app: XCUIApplication) {
        if !app.buttons[title].isHittable { app.webViews["browser.website"].swipeUp() }
        app.buttons[title].tap()
    }
    private func waitForClock(_ app: XCUIApplication, greaterThan value: Double) {
        expectation(for: NSPredicate { _, _ in self.clock(app) > value }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
    }
    private func waitForStatus(_ app: XCUIApplication, contains text: String) {
        expectation(for: NSPredicate { _, _ in app.staticTexts["browser.haptics.status"].label.contains(text) }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
    }
    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
