import XCTest

final class HapticLabUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    func testSmallScreenNavigationAndControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--music-test-library", "--reset-music-test-library"]
        app.launch()
        XCTAssertTrue(app.staticTexts["音楽プレイヤー"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["tab.experiment"].exists)
        XCTAssertFalse(app.buttons["tab.pad"].exists)
        XCTAssertFalse(app.buttons["tab.guide"].exists)
        XCTAssertTrue(app.buttons["music.demo"].exists)
        screenshot("00-music", app: app)
        app.buttons["tab.gallery"].tap()
        XCTAssertTrue(app.buttons["preset.click"].exists)
        screenshot("01-gallery", app: app)

        app.buttons["player.menu"].tap()
        screenshot("09-menu", app: app)
        app.buttons["tab.experiment"].tap()
        XCTAssertTrue(app.sliders["control.intensity"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["experiment.quickPlay"].isHittable)
        app.sliders["control.intensity"].adjust(toNormalizedSliderPosition: 0.3)
        app.buttons["kind.tap"].tap()
        XCTAssertFalse(app.sliders["control.duration"].exists)
        screenshot("02-experiment", app: app)
        app.buttons["kind.pulses"].tap()
        XCTAssertTrue(app.sliders["control.interval"].exists)

        app.navigationBars.buttons["メニュー"].tap()
        app.buttons["tab.pad"].tap()
        XCTAssertTrue(app.otherElements["touch.pad"].waitForExistence(timeout: 5))
        screenshot("03-touch-pad", app: app)
        app.buttons["tools.stop"].tap()
        XCTAssertTrue(app.staticTexts["待機中"].exists)

        app.navigationBars.buttons["メニュー"].tap()
        app.buttons["tab.guide"].tap()
        XCTAssertTrue(app.staticTexts["触感を楽しむコツ。"].waitForExistence(timeout: 5))
        screenshot("04-guide", app: app)
    }

    func testMusicFirstPreparationSavedPlaybackAndDeletion() {
        let app = XCUIApplication()
        app.launchArguments = ["--music-test-library", "--reset-music-test-library"]
        app.launch()
        let demo = app.buttons["music.demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        reveal(demo, app: app)
        demo.tap()
        XCTAssertTrue(app.staticTexts["music.firstPreparation"].waitForExistence(timeout: 5))
        screenshot("05-first-preparation", app: app)
        XCTAssertFalse(app.buttons["音楽AI"].exists)
        app.segmentedControls["analysis.profile"].buttons["オーケストラ向け"].tap()
        XCTAssertTrue(app.staticTexts["拍ごとのタップを控え、低音・クレッシェンド・余韻をなめらかな持続振動にします。"].exists)
        screenshot("12-orchestral-preparation", app: app)
        app.segmentedControls["analysis.profile"].buttons["標準"].tap()
        let prepare = app.buttons["music.prepare"]
        reveal(prepare, app: app)
        prepare.tap()
        let song = app.buttons["music.song.bundled-music-demo"]
        reveal(song, app: app)
        XCTAssertTrue(song.waitForExistence(timeout: 40))
        reveal(song, app: app)
        screenshot("06-music-prepared", app: app)
        app.terminate()
        app.launchArguments = ["--music-test-library"]
        app.launch()
        reveal(song, app: app)
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        reveal(song, app: app)
        song.tap()
        XCTAssertTrue(app.buttons["music.play"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["保存した振動を使用"].exists)
        XCTAssertTrue(app.otherElements["haptics.waveform"].exists)
        expectation(for: NSPredicate(format: "value MATCHES %@", ".*、[1-9][0-9]*区間の振動"),
                    evaluatedWith: app.otherElements["haptics.waveform"])
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.staticTexts["music.firstPreparation"].exists)
        screenshot("07-music-player", app: app)
        let play = app.buttons["music.play"]
        reveal(play, app: app)
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: play)
        waitForExpectations(timeout: 10)
        play.tap()
        app.buttons["haptics.toggle"].tap()
        XCTAssertTrue(app.otherElements["haptics.spectrum"].exists)
        screenshot("10-haptic-spectrum", app: app)
        XCTAssertTrue(app.buttons["music.stop"].exists)
        app.buttons["music.stop"].tap()
        app.buttons["閉じる"].tap()
        let navigation = app.otherElements["player.navigation"]
        let beforeKeyboard = navigation.frame.maxY
        let input = app.textFields["music.url"]
        for _ in 0..<3 { if !input.isHittable { app.swipeDown() } }
        input.tap()
        input.typeText("https://youtu.be/")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(navigation.frame.maxY, beforeKeyboard, accuracy: 4)
        XCTAssertGreaterThan(navigation.frame.minY, app.keyboards.firstMatch.frame.minY)
        screenshot("11-keyboard", app: app)
        input.typeText("\n")
        let menu = app.buttons["Pulse Garden · 12秒のサンプルの操作"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        reveal(menu, app: app)
        menu.tap()
        app.buttons["保存データを削除"].tap()
        app.alerts.buttons["削除"].tap()
        XCTAssertFalse(song.exists)
    }

    func testInvalidMusicURLAndAccountSetupAreExplicit() {
        let app = XCUIApplication()
        app.launchArguments = ["--music-test-library", "--reset-music-test-library"]
        app.launch()
        let input = app.textFields["music.url"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("https://example.com/not-a-song")
        app.buttons["music.openURL"].tap()
        XCTAssertTrue(app.staticTexts["YouTubeの動画URL、または音楽・動画ファイルのHTTPS URLを入力してください。"].waitForExistence(timeout: 5))
        app.buttons["music.account"].tap()
        XCTAssertTrue(app.staticTexts["YouTubeとつなぐ"].waitForExistence(timeout: 5))
        screenshot("08-youtube-account", app: app)
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }

    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
