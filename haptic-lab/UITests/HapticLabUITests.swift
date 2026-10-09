import XCTest

final class HapticLabUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIApplication().terminate()
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testYouTubeWebViewKeepsPlayingAcrossCorrectedSwipesAndTabChanges() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--music-test-library", "--reset-music-test-library", "--youtube-playback-fixture"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let play = app.buttons["music.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: play)
        waitForExpectations(timeout: 10)
        let webView = app.descendants(matching: .any).matching(identifier: "music.youtubeFixture").firstMatch
        let instance = webView.value as? String
        XCTAssertNotNil(instance)
        play.tap()
        let media = app.descendants(matching: .any).matching(identifier: "music.mediaPlayer").firstMatch
        swipePlayer(media, up: true)
        XCTAssertTrue(app.buttons["music.portrait"].waitForExistence(timeout: 10))
        expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(webView.value as? String, instance)
        XCTAssertFalse(app.sliders["music.seek"].exists)
        XCTAssertFalse(app.otherElements["music.landscapeControls"].exists)
        XCTAssertGreaterThanOrEqual(media.frame.height, app.frame.height - 2)
        screenshot("24-swipe-landscape-player", app: app)
        swipePlayer(media, up: false)
        XCTAssertTrue(app.buttons["music.minimize"].waitForExistence(timeout: 10))
        expectation(for: NSPredicate { _, _ in app.frame.height > app.frame.width }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(webView.value as? String, instance)
        XCTAssertEqual(play.label, "一時停止")
        swipePlayer(media, up: false)
        XCTAssertTrue(app.buttons["player.expand"].waitForExistence(timeout: 10))
        XCTAssertEqual(webView.value as? String, instance)
        XCTAssertEqual(app.buttons["player.play"].label, "一時停止")
        XCTAssertGreaterThanOrEqual(media.frame.height, 200)
        let position = app.buttons["player.expand"]
        let previous = position.value as? String
        app.buttons["tab.history"].tap()
        app.buttons["tab.search"].tap()
        expectation(for: NSPredicate { _, _ in position.value as? String != previous }, evaluatedWith: position)
        waitForExpectations(timeout: 6)
        XCTAssertEqual(app.buttons["player.play"].label, "一時停止")
        screenshot("25-video-mini-player-keeps-playing", app: app)
        app.buttons["player.expand"].tap()
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertEqual(play.label, "一時停止")
        XCTAssertEqual(webView.value as? String, instance)
        app.buttons["music.minimize"].tap()
        app.buttons["player.close"].tap()
        XCTAssertFalse(app.buttons["player.expand"].exists)
        XCTAssertFalse(webView.exists)
    }

    func testShortAndHorizontalVideoDragsRestorePortraitAndKeepTheSamePlayback() {
        let app = XCUIApplication()
        app.launchArguments = ["--music-test-library", "--reset-music-test-library", "--youtube-playback-fixture"]
        app.launch()
        let play = app.buttons["music.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: play)
        waitForExpectations(timeout: 10)
        play.tap()
        let media = app.descendants(matching: .any).matching(identifier: "music.mediaPlayer").firstMatch
        let webView = app.descendants(matching: .any).matching(identifier: "music.youtubeFixture").firstMatch
        let instance = webView.value as? String
        let start = media.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 30)),
                    withVelocity: XCUIGestureVelocity(rawValue: 50), thenHoldForDuration: 0.3)
        XCTAssertTrue(app.buttons["music.minimize"].isHittable)
        XCTAssertLessThanOrEqual(abs(media.frame.minY), 2)
        XCTAssertEqual(play.label, "一時停止")
        XCTAssertEqual(webView.value as? String, instance)
        let horizontal = media.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        horizontal.press(forDuration: 0.05, thenDragTo: horizontal.withOffset(CGVector(dx: 140, dy: 8)))
        XCTAssertTrue(app.buttons["music.minimize"].isHittable)
        XCTAssertFalse(app.buttons["music.portrait"].exists)
        XCTAssertEqual(webView.value as? String, instance)
        screenshot("27-cancelled-swipe-restores-portrait", app: app)
    }

    func testPhysicalRotationAndMinimizingDoNotPauseNativeAudio() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--music-test-library", "--reset-music-test-library", "--music-test-prepared"]
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        openPreparedPlaylist(app)
        let song = app.buttons["music.song.music-ui-fixture"]
        XCTAssertTrue(song.waitForExistence(timeout: 40))
        song.tap()
        XCTAssertTrue(app.buttons["music.minimize"].waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(app.buttons["music.portrait"].waitForExistence(timeout: 10))
        expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        screenshot("26-physical-rotation-fullscreen", app: app)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["music.minimize"].waitForExistence(timeout: 10))
        let play = app.buttons["music.play"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: play)
        waitForExpectations(timeout: 10)
        play.tap()
        app.buttons["music.minimize"].tap()
        XCTAssertTrue(app.buttons["player.expand"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["player.play"].label, "一時停止")
        let position = app.buttons["player.expand"]
        let previous = position.value as? String
        expectation(for: NSPredicate { _, _ in position.value as? String != previous }, evaluatedWith: position)
        waitForExpectations(timeout: 4)
        app.buttons["player.expand"].tap()
        XCTAssertEqual(play.label, "一時停止")
        app.buttons["music.minimize"].tap()
        app.buttons["player.play"].tap()
        XCTAssertEqual(app.buttons["player.play"].label, "音楽を再生")
        app.buttons["player.close"].tap()
        XCTAssertFalse(app.buttons["player.expand"].exists)
    }
    func testSmallScreenNavigationAndControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--music-test-library", "--reset-music-test-library"]
        app.launch()
        let title = app.staticTexts["Reson"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["ライブラリ"].exists)
        XCTAssertFalse(app.staticTexts["あなたの音楽"].exists)
        XCTAssertFalse(app.buttons["tab.experiment"].exists)
        XCTAssertFalse(app.buttons["tab.pad"].exists)
        XCTAssertFalse(app.buttons["tab.guide"].exists)
        XCTAssertFalse(app.buttons["music.import"].exists)
        XCTAssertFalse(app.buttons["music.demo"].exists)
        XCTAssertFalse(app.buttons["tab.music"].exists)
        XCTAssertFalse(app.buttons["tab.gallery"].exists)
        let input = app.textFields["music.searchQuery"]
        XCTAssertTrue(input.isHittable)
        XCTAssertGreaterThan(input.frame.minY, title.frame.maxY)
        XCTAssertLessThan(input.frame.minY - title.frame.maxY, 40)
        XCTAssertGreaterThan(app.buttons["music.account"].frame.minX, app.buttons["player.menu"].frame.maxX)
        XCTAssertFalse(app.staticTexts["接続済み"].exists)
        screenshot("00-search", app: app)
        app.buttons["player.menu"].tap()
        screenshot("09-menu", app: app)
        app.buttons["menu.gallery"].tap()
        let sample = app.buttons["preset.click"]
        XCTAssertTrue(sample.waitForExistence(timeout: 5))
        reveal(sample, app: app)
        sample.tap()
        app.buttons["tools.stop"].tap()
        screenshot("01-gallery", app: app)
        app.navigationBars.buttons["メニュー"].tap()
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

    func testSavedPlaylistPlaybackRegenerationAndDeletion() {
        let app = XCUIApplication()
        app.launchArguments = ["--music-test-library", "--reset-music-test-library", "--music-test-prepared"]
        app.launch()
        openPreparedPlaylist(app)
        let song = app.buttons["music.song.music-ui-fixture"]
        XCTAssertTrue(song.waitForExistence(timeout: 40))
        let menu = app.buttons["Playback Fixtureの操作"]
        reveal(menu, app: app)
        menu.tap()
        app.buttons["別の解析を追加"].tap()
        XCTAssertTrue(app.staticTexts["music.firstPreparation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls["analysis.quality"].exists)
        XCTAssertTrue(app.segmentedControls["analysis.method"].exists)
        XCTAssertTrue(app.staticTexts["PCでAI解析・振動を編曲"].exists)
        app.segmentedControls["analysis.method"].buttons["iPhoneで精密解析"].tap()
        XCTAssertTrue(app.staticTexts["iPhoneで精密解析（帯域別）"].exists)
        XCTAssertTrue(app.segmentedControls["analysis.style"].buttons["音に追従"].exists)
        XCTAssertTrue(app.segmentedControls["analysis.style"].buttons["リズム中心"].exists)
        XCTAssertFalse(app.buttons["高速"].exists)
        app.segmentedControls["analysis.method"].buttons["PCでAI編曲"].tap()
        screenshot("05-first-preparation", app: app)
        XCTAssertFalse(app.buttons["音楽AI"].exists)
        let profile = app.segmentedControls["analysis.profile"]
        reveal(profile, app: app)
        profile.buttons["オーケストラ向け"].tap()
        XCTAssertTrue(app.staticTexts["拍ごとのタップを控え、低音・クレッシェンド・余韻をなめらかな持続振動にします。"].exists)
        screenshot("12-orchestral-preparation", app: app)
        app.segmentedControls["analysis.profile"].buttons["標準"].tap()
        let prepare = app.buttons["music.prepare"]
        reveal(prepare, app: app)
        prepare.tap()
        expectation(for: NSPredicate { _, _ in song.isHittable }, evaluatedWith: song)
        waitForExpectations(timeout: 40)
        reveal(song, app: app)
        screenshot("06-music-prepared", app: app)
        app.terminate()
        app.launchArguments = ["--music-test-library"]
        app.launch()
        app.buttons["tab.playlists"].tap()
        app.buttons["music.preparedPlaylist"].tap()
        reveal(song, app: app)
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        reveal(song, app: app)
        song.tap()
        XCTAssertTrue(app.buttons["music.play"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["保存した振動を使用"].exists)
        XCTAssertTrue(app.staticTexts["music.analysisSummary"].label.contains("AI解析"))
        XCTAssertTrue(app.otherElements["music.arrangement"].exists)
        XCTAssertTrue(app.otherElements["haptics.waveform"].exists)
        app.buttons["haptics.toggle"].tap()
        XCTAssertTrue(app.otherElements["haptics.spectrum"].exists)
        expectation(for: NSPredicate(format: "value MATCHES %@", "24帯域、振動[0-9]+パーセント"),
                    evaluatedWith: app.otherElements["haptics.spectrum"])
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.staticTexts["music.firstPreparation"].exists)
        screenshot("07-music-player", app: app)
        XCTAssertFalse(app.sliders["music.gain"].exists)
        XCTAssertFalse(app.buttons["music.stop"].exists)
        app.buttons["music.settings"].tap()
        let gain = app.sliders["music.gain.settings"]
        reveal(gain, app: app)
        XCTAssertTrue(gain.waitForExistence(timeout: 5))
        gain.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(gain.value as? String, "400%")
        screenshot("18-strength-in-settings", app: app)
        app.buttons["完了"].tap()
        app.buttons["閉じる"].tap()
        song.tap()
        XCTAssertTrue(app.buttons["music.settings"].waitForExistence(timeout: 10))
        app.buttons["music.settings"].tap()
        reveal(gain, app: app)
        XCTAssertTrue(gain.waitForExistence(timeout: 5))
        XCTAssertEqual(gain.value as? String, "400%")
        reveal(gain, app: app)
        gain.adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(gain.value as? String, "0%")
        gain.adjust(toNormalizedSliderPosition: 0.5)
        app.buttons["完了"].tap()
        app.buttons["music.settings"].tap()
        let crispPreset = app.buttons["music.crispPreset"]
        reveal(crispPreset, app: app)
        XCTAssertTrue(crispPreset.waitForExistence(timeout: 5))
        crispPreset.tap()
        XCTAssertEqual(app.sliders["music.gain.settings"].value as? String, "80%")
        XCTAssertEqual(app.sliders["music.continuous"].value as? String, "25%")
        XCTAssertEqual(app.sliders["music.transient"].value as? String, "100%")
        XCTAssertEqual(app.sliders["music.transientSharpness"].value as? String, "90%")
        XCTAssertEqual(app.sliders["music.density"].value as? String, "100%")
        let transient = app.sliders["music.transient"]
        reveal(transient, app: app)
        transient.adjust(toNormalizedSliderPosition: 0.75)
        let savedTransient = transient.value as? String
        XCTAssertNotEqual(savedTransient, "100%")
        let sharpness = app.sliders["music.transientSharpness"]
        reveal(sharpness, app: app)
        sharpness.adjust(toNormalizedSliderPosition: 0.95)
        let savedSharpness = sharpness.value as? String
        XCTAssertNotEqual(savedSharpness, "90%")
        screenshot("19-separated-touch-controls", app: app)
        app.buttons["完了"].tap()
        app.buttons["閉じる"].tap()
        song.tap()
        XCTAssertTrue(app.buttons["music.settings"].waitForExistence(timeout: 10))
        app.buttons["music.settings"].tap()
        reveal(crispPreset, app: app)
        XCTAssertTrue(crispPreset.waitForExistence(timeout: 5))
        XCTAssertEqual(app.sliders["music.continuous"].value as? String, "25%")
        XCTAssertEqual(transient.value as? String, savedTransient)
        XCTAssertEqual(sharpness.value as? String, savedSharpness)
        app.buttons["完了"].tap()
        let play = app.buttons["music.play"]
        reveal(play, app: app)
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: play)
        waitForExpectations(timeout: 10)
        play.tap()
        screenshot("10-haptic-spectrum", app: app)
        // An arranged track opens with its composed waveform on every presentation.
        XCTAssertTrue(app.otherElements["haptics.waveform"].exists)
        app.buttons["haptics.toggle"].tap()
        XCTAssertTrue(app.otherElements["haptics.spectrum"].exists)
        app.buttons["haptics.toggle"].tap()
        XCTAssertTrue(app.otherElements["haptics.waveform"].exists)
        screenshot("13-current-haptic-waveform", app: app)
        XCTAssertFalse(app.buttons["music.stop"].exists)
        play.tap()
        XCTAssertEqual(play.label, "音楽を再生")
        app.buttons["閉じる"].tap()
        let navigation = app.otherElements["player.navigation"]
        let beforeKeyboard = navigation.frame.maxY
        app.buttons["tab.history"].tap()
        XCTAssertTrue(song.exists)
        app.buttons["tab.search"].tap()
        let input = app.textFields["music.searchQuery"]
        for _ in 0..<3 { if !input.isHittable { app.swipeDown() } }
        input.tap()
        input.typeText("https://youtu.be/")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(navigation.frame.maxY, beforeKeyboard, accuracy: 4)
        XCTAssertGreaterThan(navigation.frame.minY, app.keyboards.firstMatch.frame.minY)
        screenshot("11-keyboard", app: app)
        input.typeText("\n")
        app.buttons["tab.playlists"].tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        reveal(menu, app: app)
        menu.tap()
        app.buttons["保存データを削除"].tap()
        XCTAssertTrue(app.buttons["analysis.selectAll"].waitForExistence(timeout: 5))
        app.buttons["analysis.selectAll"].tap()
        app.buttons["analysis.deleteSelected"].tap()
        app.alerts.buttons["削除"].tap()
        XCTAssertFalse(song.exists)
    }

    func testInvalidMusicURLAndAccountSetupAreExplicit() {
        let app = XCUIApplication()
        app.launchArguments = ["--music-test-library", "--reset-music-test-library"]
        app.launch()
        let input = app.textFields["music.searchQuery"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("https://example.com/not-a-song")
        app.buttons["music.search"].tap()
        XCTAssertTrue(app.staticTexts["YouTubeの動画URL、または音楽・動画ファイルのHTTPS URLを入力してください。"].waitForExistence(timeout: 5))
        app.buttons["music.account"].tap()
        XCTAssertTrue(app.staticTexts["YouTubeとつなぐ"].waitForExistence(timeout: 5))
        screenshot("08-youtube-account", app: app)
    }

    func testSearchIsSelectableAlongsideHistoryAndPlaylists() {
        let app = XCUIApplication()
        app.launchArguments = ["--music-test-library", "--reset-music-test-library"]
        app.launch()
        let search = app.buttons["tab.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertTrue(search.isSelected)
        XCTAssertFalse(app.segmentedControls["music.librarySections"].exists)
        XCTAssertTrue(app.textFields["music.searchQuery"].exists)
        app.buttons["tab.history"].tap()
        XCTAssertTrue(app.buttons["tab.history"].isSelected)
        XCTAssertFalse(app.textFields["music.searchQuery"].exists)
        XCTAssertTrue(app.staticTexts["まだ再生履歴がありません"].exists)
        app.buttons["tab.playlists"].tap()
        XCTAssertTrue(app.buttons["tab.playlists"].isSelected)
        XCTAssertTrue(app.buttons["music.preparedPlaylist"].exists)
        XCTAssertTrue(app.staticTexts["再生リストから選ぶ"].exists)
        app.buttons["music.preparedPlaylist"].tap()
        XCTAssertTrue(app.staticTexts["まだ振動がありません"].exists)
        app.buttons["music.playlistsBack"].tap()
        search.tap()
        XCTAssertTrue(app.textFields["music.searchQuery"].exists)
    }

    func testChannelPlaylistNavigationAndVisiblePreparationCanBeMinimizedAndCancelled() {
        let app = XCUIApplication()
        app.launchArguments = ["--music-test-library", "--reset-music-test-library", "--youtube-browser-fixture", "--music-test-progress"]
        app.launch()
        let input = app.textFields["music.searchQuery"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("NHK\n")
        let channel = app.buttons["youtube.channel-UC8T8_deSUS97DWZeKO_TL9Q"]
        XCTAssertTrue(channel.waitForExistence(timeout: 10))
        reveal(channel, app: app)
        channel.tap()
        let tabs = app.segmentedControls["youtube.channelTabs"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        screenshot("14-youtube-channel", app: app)
        tabs.buttons["再生リスト"].tap()
        let playlist = app.buttons["youtube.playlist-PL-TestPlaylist"]
        XCTAssertTrue(playlist.waitForExistence(timeout: 5))
        reveal(playlist, app: app)
        playlist.tap()
        let video = app.buttons["music.song.youtube-lkiV3U0GfGg"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        reveal(video, app: app)
        screenshot("15-youtube-playlist", app: app)
        video.tap()
        XCTAssertTrue(app.staticTexts["music.firstPreparation"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["music.preparingTitle"].exists)
        XCTAssertFalse(app.buttons["music.analysisBanner"].exists)
        XCTAssertTrue(app.segmentedControls["analysis.method"].exists)
        let prepare = app.buttons["music.prepare"]
        reveal(prepare, app: app)
        prepare.tap()
        XCTAssertTrue(app.staticTexts["music.preparingTitle"].waitForExistence(timeout: 5))
        screenshot("16-visible-preparation", app: app)
        app.buttons["music.minimizePreparation"].tap()
        let banner = app.buttons["music.analysisBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.isHittable)
        screenshot("17-preparation-banner", app: app)
        banner.tap()
        let cancel = app.buttons["music.cancelAnalysis"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        reveal(cancel, app: app)
        cancel.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertFalse(banner.exists)
        let back = app.buttons["youtube.browserBack"]
        for _ in 0..<3 { if !back.isHittable { app.swipeDown() } }
        back.tap()
        for _ in 0..<3 { if !back.isHittable { app.swipeDown() } }
        back.tap()
        XCTAssertTrue(channel.exists)
    }

    func testPCAddressCanBeReplacedSavedAndRestored() {
        let app = XCUIApplication()
        app.launchArguments = ["--music-test-library", "--reset-music-test-library"]
        app.launch()
        XCTAssertTrue(app.buttons["player.menu"].waitForExistence(timeout: 10))
        app.buttons["player.menu"].tap()
        app.buttons["menu.analysis"].tap()
        let address = app.textFields["analysis.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        reveal(app.buttons["analysis.clearAddress"], app: app)
        app.buttons["analysis.clearAddress"].tap()
        address.typeText("http://192.168.1.12:8765\n")
        let done = app.buttons["入力を終了"]
        if done.exists { done.tap() }
        let save = app.buttons["analysis.saveConnection"]
        reveal(save, app: app)
        save.tap()
        XCTAssertTrue(app.staticTexts["接続設定を保存しました: http://192.168.1.12:8765"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--music-test-library"]
        app.launch()
        XCTAssertTrue(app.buttons["player.menu"].waitForExistence(timeout: 10))
        app.buttons["player.menu"].tap()
        app.buttons["menu.analysis"].tap()
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        XCTAssertEqual(address.value as? String, "http://192.168.1.12:8765")
    }

    func testGlobalVibrationSettingsAndOneButtonResetContinueFollowingAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--music-test-library", "--reset-music-test-library", "--music-test-prepared"]
        app.launch()
        openPreparedPlaylist(app)
        let song = app.buttons["music.song.music-ui-fixture"]
        XCTAssertTrue(song.waitForExistence(timeout: 40))
        app.buttons["player.menu"].tap()
        app.buttons["menu.globalSettings"].tap()
        let globalPreset = app.buttons["global.crispPreset"]
        XCTAssertTrue(globalPreset.waitForExistence(timeout: 5))
        reveal(globalPreset, app: app)
        globalPreset.tap()
        app.navigationBars.buttons["メニュー"].tap()
        app.buttons["閉じる"].tap()
        reveal(song, app: app)
        song.tap()
        XCTAssertTrue(app.buttons["music.settings"].waitForExistence(timeout: 10))
        app.buttons["music.settings"].tap()
        let gain = app.sliders["music.gain.settings"]
        reveal(gain, app: app)
        XCTAssertTrue(gain.waitForExistence(timeout: 5))
        XCTAssertEqual(gain.value as? String, "80%")
        gain.adjust(toNormalizedSliderPosition: 1)
        app.buttons["完了"].tap()
        app.buttons["music.settings"].tap()
        let scope = app.staticTexts["music.settingsScope"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        XCTAssertEqual(scope.label, "この曲の個別設定")
        reveal(app.buttons["music.resetToGlobal"], app: app)
        app.buttons["music.resetToGlobal"].tap()
        XCTAssertEqual(scope.label, "グローバル設定を使用中")
        screenshot("20-global-settings-reset", app: app)
        reveal(gain, app: app)
        XCTAssertEqual(gain.value as? String, "80%")
        app.buttons["完了"].tap()
        app.buttons["閉じる"].tap()
        app.buttons["player.menu"].tap()
        app.buttons["menu.globalSettings"].tap()
        let globalGain = app.sliders["global.gain.settings"]
        XCTAssertTrue(globalGain.waitForExistence(timeout: 5))
        reveal(globalGain, app: app)
        globalGain.adjust(toNormalizedSliderPosition: 0)
        app.navigationBars.buttons["メニュー"].tap()
        app.buttons["閉じる"].tap()
        reveal(song, app: app)
        song.tap()
        XCTAssertTrue(app.buttons["music.settings"].waitForExistence(timeout: 10))
        app.buttons["music.settings"].tap()
        reveal(gain, app: app)
        XCTAssertTrue(gain.waitForExistence(timeout: 5))
        XCTAssertEqual(gain.value as? String, "0%")
        app.terminate()
        app.launchArguments = ["--music-test-library"]
        app.launch()
        app.buttons["tab.playlists"].tap()
        app.buttons["music.preparedPlaylist"].tap()
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        reveal(song, app: app)
        song.tap()
        XCTAssertTrue(app.buttons["music.settings"].waitForExistence(timeout: 10))
        app.buttons["music.settings"].tap()
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        XCTAssertEqual(scope.label, "グローバル設定を使用中")
        XCTAssertFalse(app.buttons["music.resetToGlobal"].isEnabled)
        reveal(gain, app: app)
        XCTAssertTrue(gain.waitForExistence(timeout: 5))
        XCTAssertEqual(gain.value as? String, "0%")
    }

    func testAnalysisComparisonsSwitchPersistAndDeleteOnlyTwoSelectedResults() {
        let app = XCUIApplication()
        app.launchArguments = ["--music-test-library", "--reset-music-test-library", "--music-test-prepared", "--music-test-variants"]
        app.launch()
        openPreparedPlaylist(app)
        let song = app.buttons["music.song.music-ui-fixture"]
        XCTAssertTrue(song.waitForExistence(timeout: 40))
        let preparation = app.buttons["music.analysisBanner"]
        if preparation.exists { expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: preparation); waitForExpectations(timeout: 40) }
        song.tap()
        XCTAssertTrue(app.buttons["music.settings"].waitForExistence(timeout: 10))
        app.buttons["music.settings"].tap()
        let count = app.staticTexts["music.analysisCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        expectation(for: NSPredicate { _, _ in count.label.hasPrefix("3件") }, evaluatedWith: count)
        waitForExpectations(timeout: 40)
        app.buttons["music.analysisVariant"].tap()
        let device = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "iPhone · 音に追従")).firstMatch
        XCTAssertTrue(device.waitForExistence(timeout: 5))
        device.tap()
        XCTAssertTrue(app.staticTexts["music.activeAnalysis"].label.hasPrefix("iPhone"))
        app.terminate()
        app.launchArguments = ["--music-test-library"]
        app.launch()
        app.buttons["tab.playlists"].tap()
        app.buttons["music.preparedPlaylist"].tap()
        XCTAssertTrue(song.waitForExistence(timeout: 10))
        reveal(song, app: app)
        song.tap()
        XCTAssertTrue(app.buttons["music.settings"].waitForExistence(timeout: 10))
        app.buttons["music.settings"].tap()
        XCTAssertTrue(app.staticTexts["music.activeAnalysis"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["music.activeAnalysis"].label.hasPrefix("iPhone"))
        app.buttons["music.deleteAnalyses"].tap()
        let pcOptions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "analysis.deleteOption.", "PC"))
        XCTAssertEqual(pcOptions.count, 2)
        for index in 0..<2 { pcOptions.element(boundBy: index).tap() }
        screenshot("21-analysis-comparison-delete", app: app)
        app.buttons["analysis.deleteSelected"].tap()
        app.alerts.buttons["削除"].tap()
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertTrue(count.label.hasPrefix("1件"))
        XCTAssertTrue(app.staticTexts["music.activeAnalysis"].label.hasPrefix("iPhone"))
    }

    func testCompletedAnalysisKeepsTheOpenYouTubePlaylistAndSearchTab() {
        let app = XCUIApplication()
        app.launchArguments = ["--music-test-library", "--reset-music-test-library", "--youtube-browser-fixture", "--music-test-completion"]
        app.launch()
        let input = app.textFields["music.searchQuery"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("NHK\n")
        let channel = app.buttons["youtube.channel-UC8T8_deSUS97DWZeKO_TL9Q"]
        XCTAssertTrue(channel.waitForExistence(timeout: 10))
        reveal(channel, app: app)
        channel.tap()
        app.segmentedControls["youtube.channelTabs"].buttons["再生リスト"].tap()
        let playlist = app.buttons["youtube.playlist-PL-TestPlaylist"]
        XCTAssertTrue(playlist.waitForExistence(timeout: 5))
        reveal(playlist, app: app)
        playlist.tap()
        let video = app.buttons["music.song.youtube-lkiV3U0GfGg"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        reveal(video, app: app)
        video.tap()
        XCTAssertTrue(app.staticTexts["music.firstPreparation"].waitForExistence(timeout: 5))
        let prepare = app.buttons["music.prepare"]
        reveal(prepare, app: app)
        prepare.tap()
        XCTAssertTrue(app.staticTexts["保存した振動を使用"].waitForExistence(timeout: 40))
        let media = app.descendants(matching: .any).matching(identifier: "music.mediaPlayer").firstMatch
        XCTAssertTrue(media.waitForExistence(timeout: 5))
        XCTAssertEqual(media.frame.width, app.frame.width, accuracy: 2)
        XCTAssertEqual(media.frame.height, max(200, app.frame.width * 9 / 16), accuracy: 2)
        XCTAssertLessThan(media.frame.minY, 80)
        XCTAssertFalse(app.sliders["music.gain"].exists)
        XCTAssertFalse(app.buttons["music.stop"].exists)
        screenshot("23-large-video-player", app: app)
        app.buttons["閉じる"].tap()
        expectation(for: NSPredicate { _, _ in video.isHittable && !app.buttons["music.analysisBanner"].exists }, evaluatedWith: video)
        waitForExpectations(timeout: 40)
        XCTAssertTrue(app.buttons["tab.search"].isSelected)
        XCTAssertFalse(app.buttons["tab.playlists"].isSelected)
        XCTAssertTrue(app.buttons["youtube.browserBack"].exists)
        XCTAssertTrue(app.staticTexts["テスト再生リスト"].exists)
        XCTAssertFalse(app.buttons["music.playlistsBack"].exists)
        screenshot("22-analysis-completion-keeps-playlist", app: app)
        reveal(video, app: app)
        video.tap()
        XCTAssertTrue(app.staticTexts["保存した振動を使用"].waitForExistence(timeout: 10))
    }

    private func openPreparedPlaylist(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["tab.playlists"].waitForExistence(timeout: 10))
        app.buttons["tab.playlists"].tap()
        app.buttons["music.preparedPlaylist"].tap()
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { return }
            let scroll = app.scrollViews.firstMatch
            if scroll.exists && scroll.isHittable { scroll.swipeUp() }
            else { app.swipeUp() }
        }
    }

    private func swipePlayer(_ element: XCUIElement, up: Bool) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.8 : 0.3))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.3 : 0.8))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    private func screenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
