#if DEBUG
import Foundation

enum BrowserFixtures {
    static var duration: Double { ProcessInfo.processInfo.arguments.contains("--browser-haptics-fixture") ? 180 : 60 }
    static let firstID = "lkiV3U0GfGg"
    static let nextID = "dQw4w9WgXcQ"

    @MainActor static func makeLibrary() -> MusicLibrary {
        guard ProcessInfo.processInfo.arguments.contains("--browser-haptics-fixture") else { return MusicLibrary() }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BrowserHapticUITests", isDirectory: true)
        if ProcessInfo.processInfo.arguments.contains("--reset-browser-haptics-fixture") {
            try? FileManager.default.removeItem(at: root)
            UserDefaults.standard.removeObject(forKey: "browser.haptics.enabled")
        }
        var services = MusicPreparationServices()
        services.analyzeOnPC = { _, _, _, _, _, progress in
            progress(0.5, "テスト用の振動を作成中")
            try await Task.sleep(nanoseconds: 800_000_000)
            return track()
        }
        return MusicLibrary(root: root, services: services)
    }

    static func track() -> MusicHapticTrack {
        MusicHapticTrack(version: 2, audioSHA256: String(repeating: "a", count: 64), duration: duration,
            envelope: stride(from: 0.0, to: duration, by: 0.5).map {
                MusicEnvelopePoint(time: $0, bass: 0.4, energy: 0.6, sharpness: 0.5, mid: 0.3, high: 0.2)
            }, taps: stride(from: 0.0, to: duration, by: 0.5).map { MusicTap(time: $0, intensity: 0.8, sharpness: 0.9) },
            analysis: MusicAnalysisInfo(engine: "pc", elapsedSeconds: 0.8, sampleRate: 44_100, hopMilliseconds: 10,
                                        fftSize: 4_096, style: .arranged, profile: .standard))
    }

    // A real HTML media clock, not an injected native snapshot or mocked playback properties.
    private static func audio() -> String {
        guard let url = Bundle.main.url(forResource: "BrowserFixture", withExtension: "mp4"),
              let data = try? Data(contentsOf: url) else { return "" }
        return "data:video/mp4;base64," + data.base64EncodedString()
    }

    static func html(url: URL) -> String {
        let isWatch = url.path == "/watch"
        let heading = url.path == "/feed/history" ? "視聴履歴" : url.path == "/feed/playlists" ? "あなたの再生リスト" : isWatch ? "テスト動画" : "YouTube"
        let player = isWatch ? """
        <div id="movie_player"><video playsinline controls preload="auto" src="\(audio())"></video></div>
        <p><button onclick="document.querySelector('video').play()">動画を再生</button>
        <button onclick="document.querySelector('video').pause()">一時停止</button>
        <button onclick="document.querySelector('video').currentTime=20">20秒へ移動</button>
        <button onclick="document.getElementById('movie_player').classList.toggle('ad-showing')">広告を切り替え</button></p>
        <p><a href="https://www.youtube.com/watch?v=\(nextID)">次の動画</a></p>
        """ : "<div class=\"video\">▶</div>"
        return """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>\(heading) - YouTube</title>
        <style>html,body{margin:0;background:#0f0f0f;color:white;font:16px system-ui}header{padding:18px;font-size:24px;font-weight:700}
        .video,video{margin:16px;width:calc(100% - 32px);height:175px;background:linear-gradient(135deg,#18232b,#3d2442);border-radius:12px}
        .video{display:flex;align-items:center;justify-content:center;font-size:42px}
        p{margin:12px 16px;color:#aaa}a{color:#9cddce}button{padding:10px;margin:3px;color:white;background:#333;border:0;border-radius:8px}</style>
        </head><body><header>\(heading)</header>\(player)
        <p>UI Preview · オフラインの画面確認用</p><p><a href="https://www.youtube.com/watch?v=\(firstID)">Preview video</a></p></body></html>
        """
    }
}
#endif
