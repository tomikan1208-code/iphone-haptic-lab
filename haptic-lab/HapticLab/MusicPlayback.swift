import AVFoundation
import CoreHaptics
import QuartzCore
import SwiftUI
import WebKit

@MainActor
final class MusicPlayback: ObservableObject {
    @Published private(set) var mediaSessionID = UUID()
    @Published private(set) var selection: MusicSelection?
    @Published private(set) var isPlaying = false
    @Published private(set) var isReady = false
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var hasHaptics = false
    @Published private(set) var analysisVariantID: String?
    @Published private(set) var isBuffering = false
    @Published private(set) var containsVideo = false
    @Published var message: String?
    @Published var settings = MusicSettings() { didSet { renderer.settings = settings.normalized } }
    let player = AVPlayer()
    let renderer = MusicHapticRenderer()
    weak var webView: WKWebView?
    var onPlay: ((MusicSelection) -> Void)?
    private var track: MusicHapticTrack?
    private var mediaClock = MusicMediaClock()
    var visualizationTrack: MusicHapticTrack? { track }
    var visualizationPosition: Double { min(duration, max(0, mediaClock.position(at: CACurrentMediaTime()))) }
    var hapticsActive: Bool { isPlaying && !isBuffering && seekTarget == nil && renderer.isRendering }
    private var observer: Any?
    private var statusObserver: NSKeyValueObservation?
    private var controlObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var loggedPlay = false
    private var durationGate = MusicDurationGate()
    private var durationMessage: String?
    private var seekTarget: Double?
    private var seekDeadline = 0.0
    private var seekGeneration = 0

    init() {
        renderer.onFailure = { [weak self] text in self?.pause(); self?.message = text }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.02, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in self?.nativeSnapshot(time: time.seconds) }
        }
        controlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, self.selection?.kind != .youtube else { return }
                self.nativeSnapshot(time: self.player.currentTime().seconds)
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.pause() }
            }
        routeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.pause() }
            }
    }

    func load(_ selection: MusicSelection, track: MusicHapticTrack?, mediaURL: URL?, settings: MusicSettings, variantID: String? = nil) {
        stop()
        mediaSessionID = UUID()
        self.selection = selection
        self.track = track
        analysisVariantID = variantID
        containsVideo = selection.kind == .youtube
        self.settings = settings.normalized
        hasHaptics = track != nil
        duration = selection.duration ?? track?.duration ?? 0
        position = 0
        message = nil
        loggedPlay = false
        durationGate.reset()
        durationMessage = nil
        seekTarget = nil
        isReady = false
        if selection.kind != .youtube {
            guard let url = mediaURL ?? URL(string: selection.url) else {
                message = "再生する音源が見つかりません。"
                return
            }
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            Task { [weak self, weak item] in
                guard let item else { return }
                let videoTracks = try? await item.asset.loadTracks(withMediaType: .video)
                guard let self, self.player.currentItem === item else { return }
                self.containsVideo = !(videoTracks ?? []).isEmpty
            }
            statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
                Task { @MainActor [weak self, weak item] in
                    guard let self, let item, self.player.currentItem === item else { return }
                    self.isReady = item.status == .readyToPlay
                    if item.status == .failed { self.pause(); self.message = item.error?.localizedDescription ?? "音源を再生できませんでした。" }
                }
            }
            endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                object: item, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.pause() }
                }
        }
    }

    func toggle() { isPlaying ? pause() : play() }

    func switchAnalysis(_ track: MusicHapticTrack, variantID: String) throws {
        let validated = try track.validated()
        renderer.stop()
        self.track = validated
        analysisVariantID = variantID
        hasHaptics = true
        durationGate.reset()
        clearDurationWaiting()
        loggedPlay = false
        // Keep the media player and clock running; the next snapshot resumes haptics.
    }

    func play() {
        guard selection != nil, isReady else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            if duration > 0, position >= duration - 0.1 { seek(to: 0) }
            if selection?.kind == .youtube { evaluate("player.playVideo()") } else { player.play() }
        } catch { message = error.localizedDescription }
    }

    func pause() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--youtube-playback-fixture") {
            print("Playback fixture paused: \(Thread.callStackSymbols.prefix(8).joined(separator: " | "))")
        }
        #endif
        player.pause()
        if selection?.kind == .youtube { evaluate("player.pauseVideo()") }
        isPlaying = false
        isBuffering = false
        mediaClock.reset(to: position)
        renderer.stop()
        durationGate.reset()
        seekGeneration += 1
        seekTarget = nil
    }

    func stop() {
        pause()
        statusObserver = nil
        player.replaceCurrentItem(with: nil)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver); self.endObserver = nil }
        if let webView {
            // Stop the old iframe immediately, including when changing between two YouTube songs.
            webView.evaluateJavaScript("if(window.player && player.stopVideo) player.stopVideo()", completionHandler: nil)
        }
        webView = nil
        selection = nil
        track = nil
        analysisVariantID = nil
        hasHaptics = false
        isReady = false
        position = 0
        mediaClock.reset()
        duration = 0
    }

    func suspend() {
        pause()
        renderer.suspend()
        if selection != nil { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    func seek(to time: Double) {
        guard time.isFinite, duration > 0 else { return }
        let target = min(duration, max(0, time))
        renderer.stop()
        seekGeneration += 1
        let generation = seekGeneration
        seekTarget = target
        seekDeadline = CACurrentMediaTime() + 5
        position = target
        mediaClock.reset(to: target)
        if selection?.kind == .youtube { evaluate("player.seekTo(\(target),true)") }
        else {
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                Task { @MainActor [weak self] in
                    guard let self, self.seekGeneration == generation else { return }
                    if finished { self.seekTarget = nil }
                }
            }
        }
    }

    func beginYouTubeLoading(videoID: String) {
        if selection?.videoID == videoID { isReady = false; durationGate.reset(); renderer.stop() }
    }

    func receiveYouTube(_ snapshot: [String: Any], videoID: String) {
        guard selection?.videoID == videoID else { return }
        if let error = snapshot["error"] as? Int {
            pause()
            isReady = false
            message = error == 153 ? "YouTubeがアプリの再生元を確認できませんでした。YouTubeで開いてください。" :
                "この動画をアプリ内で再生できません（YouTube: \(error)）。公開状態や埋め込みの許可を確認してください。"
            return
        }
        if snapshot["ready"] as? Bool == true, !isReady { isReady = true }
        guard let state = snapshot["state"] as? Int, let time = snapshot["time"] as? Double,
              let span = snapshot["duration"] as? Double, let rate = snapshot["rate"] as? Double,
              let sent = snapshot["sent"] as? Double, time.isFinite, span.isFinite, sent.isFinite else { return }
        let latency = Date().timeIntervalSince1970 - sent / 1_000
        guard (-0.1...0.35).contains(latency), rate.isFinite, (0.25...2).contains(rate) else {
            durationGate.reset(); renderer.stop(); mediaClock.reset(to: position); return
        }
        let currentID = snapshot["videoID"] as? String
        // Ignore the clock/duration of an unloaded iframe or another video. These
        // snapshots previously replaced the selected song's duration and raised a
        // mismatch even when the selected song was not playing.
        guard currentID == videoID, span > 0, [0, 1, 2].contains(state) else {
            if isPlaying { isPlaying = false }
            if isBuffering != (state == 3) { isBuffering = state == 3 }
            durationGate.reset()
            renderer.stop()
            mediaClock.reset(to: position)
            return
        }
        let playing = state == 1
        if isPlaying != playing { isPlaying = playing }
        if isBuffering { isBuffering = false }
        if let track {
            let result = durationGate.check(duration: span, expected: track.duration,
                                            playing: playing, hostTime: CACurrentMediaTime())
            guard result == .matching else {
                renderer.stop()
                mediaClock.reset(to: position)
                if result == .different {
                    showDurationWaiting(videoDuration: span, audioDuration: track.duration)
                }
                return
            }
        }
        clearDurationWaiting()
        if abs(position - max(0, time)) > 0.02 { position = max(0, time) }
        if abs(duration - span) > 0.001 { duration = span }
        let correctedTime = max(0, time + (playing ? max(0, latency) * rate : 0))
        mediaClock.update(position: correctedTime, playing: playing, rate: rate, hostTime: CACurrentMediaTime(), clockPosition: time)
        synchronize(position: visualizationPosition, playing: playing, rate: rate, clockPosition: time)
    }

    private func nativeSnapshot(time observed: Double) {
        let latest = player.currentTime().seconds
        let time = latest.isFinite ? latest : observed
        guard selection != nil, selection?.kind != .youtube, time.isFinite else { return }
        if abs(position - max(0, time)) > 0.02 { position = max(0, time) }
        if let span = player.currentItem?.duration.seconds, span.isFinite, span > 0, abs(duration - span) > 0.001 { duration = span }
        let playing = player.timeControlStatus == .playing
        let buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if isPlaying != playing { isPlaying = playing }
        if isBuffering != buffering { isBuffering = buffering }
        mediaClock.update(position: max(0, time), playing: playing, rate: Double(player.rate), hostTime: CACurrentMediaTime())
        synchronize(position: max(0, time), playing: playing, rate: Double(player.rate))
    }

    private func synchronize(position: Double, playing: Bool, rate: Double, clockPosition: Double? = nil) {
        guard duration > 0 else { renderer.stop(); return }
        if let seekTarget {
            if abs(position - seekTarget) <= 0.5 { self.seekTarget = nil }
            else {
                renderer.stop()
                if CACurrentMediaTime() > seekDeadline { pause(); message = "指定した位置へ移動できませんでした。もう一度再生してください。" }
                return
            }
        }
        if playing, !loggedPlay, let selection { loggedPlay = true; onPlay?(selection) }
        if playing, let track, duration > 0, abs(duration - track.duration) > max(1, track.duration * 0.015) {
            renderer.stop()
            showDurationWaiting(videoDuration: duration, audioDuration: track.duration)
            return
        }
        clearDurationWaiting()
        renderer.synchronize(track: track, position: position, playing: playing, rate: rate, clockPosition: clockPosition)
    }

    private func showDurationWaiting(videoDuration: Double, audioDuration: Double) {
        let text = "再生中の長さを確認しています（動画 \(musicTime(videoDuration))・解析 \(musicTime(audioDuration))）。一致したら振動を自動で再開します。"
        guard durationMessage != text else { return }
        // Do not overwrite playback/network errors with a duration diagnostic.
        if message == nil || message == durationMessage { message = text }
        durationMessage = text
    }

    private func clearDurationWaiting() {
        if let durationMessage, message == durationMessage { message = nil }
        durationMessage = nil
    }

    private func evaluate(_ command: String) {
        webView?.evaluateJavaScript("if(window.player && player.playVideo) { \(command); }", completionHandler: nil)
    }
}

struct YouTubeMusicPlayer: UIViewRepresentable {
    let videoID: String
    @ObservedObject var playback: MusicPlayback
    var showsControls = false

    func makeCoordinator() -> Coordinator { Coordinator(playback: playback, videoID: videoID, showsControls: showsControls) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "musicPlayer")
        let origin = "https://\(Bundle.main.bundleIdentifier ?? "com.tomikan1208.hapticlab")"
        configuration.userContentController.addUserScript(YouTubePlayerControls.script(origin: origin))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = showsControls
        playback.webView = webView
        context.coordinator.webView = webView
        playback.beginYouTubeLoading(videoID: videoID)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--youtube-playback-fixture") {
            webView.isAccessibilityElement = true
            webView.accessibilityIdentifier = "music.youtubeFixture"
            webView.accessibilityValue = UUID().uuidString
            print("Playback fixture WebView created: \(webView.accessibilityValue ?? "")")
            webView.loadHTMLString(Self.playbackFixtureHTML(videoID: videoID, showsControls: showsControls), baseURL: URL(string: origin))
            return webView
        }
        #endif
        // The bundle-ID HTTPS base supplies the app identity required by YouTube (error 153).
        webView.loadHTMLString(Self.html(videoID: videoID, origin: origin, showsControls: showsControls), baseURL: URL(string: origin))
        return webView
    }

    #if DEBUG
    /// An offline clock exercises the same WebView lifecycle and message bridge without a YouTube account.
    private static func playbackFixtureHTML(videoID: String, showsControls: Bool) -> String {
        """
        <html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{height:100%;margin:0;background:#101d22;color:#8ff0cf;font:24px system-ui}
        body{display:flex;align-items:center;justify-content:center}
        #fixture-controls{position:fixed;left:20px;right:20px;bottom:12px;font:14px system-ui}
        #fixture-controls input{width:75%}button{font:14px system-ui}</style></head><body>Playback Fixture
        <div id="fixture-controls" hidden><input type="range" min="0" max="120" aria-label="YouTubeの再生位置"
          oninput="player.seekTo(Number(this.value))"><button onclick="this.textContent='速度・画質'">YouTubeの設定</button></div><script>
        var state=2,position=0,started=performance.now(),timer;
        function setResonControls(visible){document.getElementById('fixture-controls').hidden=!visible}
        setResonControls(\(showsControls ? "true" : "false"));
        function time(){return position+(state===1?(performance.now()-started)/1000:0)}
        function send(extra){window.webkit.messageHandlers.musicPlayer.postMessage(Object.assign({state:state,time:time(),
          duration:120,rate:1,videoID:'\(videoID)',sent:Date.now()},extra||{}))}
        var player={playVideo:function(){started=performance.now();state=1;send()},
          pauseVideo:function(){position=time();state=2;send()},stopVideo:function(){position=0;state=2;send()},
          seekTo:function(value){position=value;started=performance.now();send()},destroy:function(){clearInterval(timer)}};
        timer=setInterval(function(){send()},20);send({ready:true});
        </script></body></html>
        """
    }
    #endif

    static func html(videoID: String, origin: String, showsControls: Bool = false) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;background:#000;height:100%;overflow:hidden}#player{width:100%;height:100%}</style></head>
        <body><div id="player"></div><script>
        var player, timer, resonControls = \(showsControls ? "true" : "false");
        function setResonControls(visible) {
          resonControls = visible === true;
          try {
            const frame = player && player.getIframe ? player.getIframe() : document.getElementById('player');
            if (!frame || frame.tagName !== 'IFRAME') return;
            const destination = new URL(frame.src);
            if (destination.protocol !== 'https:' || !(destination.hostname === 'youtube.com' ||
                destination.hostname.endsWith('.youtube.com'))) return;
            frame.style.pointerEvents = resonControls ? 'auto' : 'none';
            frame.contentWindow.postMessage({type:'reson-player-controls',visible:resonControls},destination.origin);
          } catch(e) {}
          if (!resonControls) disableCaptions();
        }
        window.addEventListener('message', function(event) {
          if (!event.data || event.data.type !== 'reson-player-controls-ready') return;
          const frame = document.getElementById('player');
          if (frame && event.source === frame.contentWindow && event.origin === new URL(frame.src).origin)
            setResonControls(resonControls);
        });
        function disableCaptions() {
          // Module unloading is not a documented guarantee. Keep playback working when it is unavailable.
          try {
            if (!resonControls && player && typeof player.unloadModule === 'function' && typeof player.getOptions === 'function' &&
                player.getOptions().indexOf('captions') !== -1) player.unloadModule('captions');
          } catch(e) {}
        }
        function send(extra) {
          try {
            var data = {state:player.getPlayerState(),time:player.getCurrentTime(),duration:player.getDuration(),
              rate:player.getPlaybackRate(),videoID:player.getVideoData().video_id,sent:Date.now()};
            Object.assign(data,extra||{}); window.webkit.messageHandlers.musicPlayer.postMessage(data);
          } catch(e) {}
        }
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player',{videoId:'\(videoID)',width:'100%',height:'100%',
            playerVars:{playsinline:1,autoplay:0,controls:1,fs:0,disablekb:1,rel:0,iv_load_policy:3,cc_load_policy:0,origin:'\(origin)'},
            events:{onReady:function(){setResonControls(resonControls);disableCaptions();send({ready:true});timer=setInterval(function(){send()},20)},
              onApiChange:function(){disableCaptions()},
              onStateChange:function(){disableCaptions();send()},onPlaybackRateChange:function(){send()},
              onError:function(e){window.webkit.messageHandlers.musicPlayer.postMessage({error:e.data})}}});
        }
        </script><script src="https://www.youtube.com/iframe_api"></script></body></html>
        """
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard context.coordinator.showsControls != showsControls else { return }
        context.coordinator.showsControls = showsControls
        context.coordinator.applyControls()
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.evaluateJavaScript("clearInterval(timer); if(window.player && player.destroy) player.destroy()", completionHandler: nil)
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "musicPlayer")
        uiView.stopLoading()
        if coordinator.playback?.webView === uiView { coordinator.playback?.renderer.stop() }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var playback: MusicPlayback?
        weak var webView: WKWebView?
        let videoID: String
        var showsControls: Bool
        init(playback: MusicPlayback, videoID: String, showsControls: Bool) {
            self.playback = playback; self.videoID = videoID; self.showsControls = showsControls
        }
        func applyControls() {
            webView?.isUserInteractionEnabled = showsControls
            webView?.evaluateJavaScript("if(window.setResonControls) setResonControls(\(showsControls ? "true" : "false"))", completionHandler: nil)
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let data = message.body as? [String: Any] else { return }
            Task { @MainActor [weak self] in
                guard let self, let webView = self.webView, self.playback?.webView === webView else { return }
                if data["ready"] as? Bool == true { self.applyControls() }
                self.playback?.receiveYouTube(data, videoID: self.videoID)
            }
        }
    }
}
