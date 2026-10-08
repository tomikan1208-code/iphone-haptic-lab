import Combine
import QuartzCore
import SwiftUI

@MainActor
protocol BrowserHapticRendering: AnyObject {
    var supported: Bool { get }
    var settings: MusicSettings { get set }
    var onFailure: ((String) -> Void)? { get set }
    func synchronize(track: MusicHapticTrack?, position: Double, playing: Bool, rate: Double, clockPosition: Double?)
    func stop()
    func suspend()
}

extension MusicHapticRenderer: BrowserHapticRendering {}

@MainActor
final class BrowserHaptics: ObservableObject {
    enum Status: Equatable {
        case idle, needsPreparation, ready, playing, paused, buffering, advertisement, disabled, mismatch, waiting, unsupported
        var title: String {
            switch self {
            case .idle: return "動画を開いて振動を作成"
            case .needsPreparation: return "この動画の振動を作成"
            case .ready: return "振動の準備ができました"
            case .playing: return "YouTubeの再生に同期中"
            case .paused: return "一時停止中"
            case .buffering: return "読み込み中 · 振動を待機"
            case .advertisement: return "広告中 · 振動を待機"
            case .disabled: return "振動オフ"
            case .mismatch: return "動画と振動の長さが一致しません"
            case .waiting: return "再生位置を確認中"
            case .unsupported: return "この端末は振動に対応していません"
            }
        }
    }

    @Published private(set) var selection: MusicSelection?
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var videoPlaying = false
    @Published private(set) var status: Status = .idle
    @Published private(set) var isSynchronizing = false
    @Published var message: String?
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "browser.haptics.enabled")
            if enabled { synchronizeLastSnapshot() }
            else { renderer.stop(); isSynchronizing = false; status = .disabled }
        }
    }
    var supported: Bool { renderer.supported }
    var record: MusicRecord? { selection.flatMap { library.record(for: $0) } }
    var settings: MusicSettings { selection.map { library.settings(for: $0.id) } ?? library.globalSettings }

    private let library: MusicLibrary
    private let renderer: BrowserHapticRendering
    private let defaults: UserDefaults
    private var subscription: AnyCancellable?
    private var track: MusicHapticTrack?
    private var trackFilename: String?
    private var lastSnapshot: WebPlaybackSnapshot?
    private var lastSampleHost = 0.0
    private var lastPublishedHost = 0.0
    private var foreground = true
    private var durationGate = MusicDurationGate()
    private var historySaved = false
    private var timer: Timer?

    init(library: MusicLibrary, renderer: BrowserHapticRendering? = nil, defaults: UserDefaults = .standard) {
        self.library = library
        self.renderer = renderer ?? MusicHapticRenderer()
        self.defaults = defaults
        enabled = defaults.object(forKey: "browser.haptics.enabled") as? Bool ?? true
        self.renderer.onFailure = { [weak self] text in
            self?.message = text
            self?.isSynchronizing = false
            self?.status = .waiting
        }
        subscription = Publishers.CombineLatest(library.$records, library.$globalSettings).dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPreparedTrack() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkFreshness() }
        }
    }

    func attach(to browser: YouTubeBrowser) {
        browser.onPlayback = { [weak self] snapshot in self?.receive(snapshot) }
        browser.onPlaybackDisconnected = { [weak self] in self?.disconnect() }
    }

    deinit { timer?.invalidate() }

    func receive(_ snapshot: WebPlaybackSnapshot, hostTime: Double = CACurrentMediaTime()) {
        if snapshot.videoID != selection?.videoID {
            renderer.stop()
            durationGate.reset()
            track = nil
            trackFilename = nil
            historySaved = false
            message = nil
            selection = snapshot.selection
            loadPreparedTrack()
        } else if let updated = snapshot.selection, updated != selection {
            selection = updated
        }
        lastSnapshot = snapshot
        lastSampleHost = hostTime
        // Render at the website's sample rate, but avoid rebuilding the native UI 50 times/second.
        if hostTime - lastPublishedHost >= 1 || videoPlaying != snapshot.playing {
            if abs(position - snapshot.position) > 0.02 { position = snapshot.position }
            if abs(duration - snapshot.duration) > 0.001 { duration = snapshot.duration }
            if videoPlaying != snapshot.playing { videoPlaying = snapshot.playing }
            lastPublishedHost = hostTime
        }
        synchronize(snapshot, hostTime: hostTime)
    }

    func disconnect() {
        renderer.stop()
        lastSnapshot = nil
        durationGate.reset()
        isSynchronizing = false
        videoPlaying = false
        position = 0
        duration = 0
        selection = nil
        track = nil
        trackFilename = nil
        historySaved = false
        status = .idle
    }

    func setForeground(_ value: Bool) {
        foreground = value
        if !value {
            renderer.suspend()
            lastSnapshot = nil
            isSynchronizing = false
            videoPlaying = false
            status = .waiting
        }
        // Fresh website samples resume synchronization; never resume from an old clock.
    }

    func refreshPreparedTrack() {
        loadPreparedTrack()
        synchronizeLastSnapshot()
    }

    func saveSettings(_ settings: MusicSettings) {
        guard let selection else { return }
        library.saveSettings(settings, id: selection.id)
        refreshPreparedTrack()
    }

    private func loadPreparedTrack() {
        renderer.settings = settings
        let filename = record?.trackFilename
        guard filename != trackFilename else { return }
        renderer.stop()
        durationGate.reset()
        trackFilename = filename
        track = nil
        guard let record, record.isPrepared else { return }
        do { track = try library.disk.track(record) }
        catch { message = error.localizedDescription }
    }

    private func synchronizeLastSnapshot() {
        guard let lastSnapshot, CACurrentMediaTime() - lastSampleHost <= 0.35 else {
            renderer.stop(); isSynchronizing = false
            status = selection == nil ? .idle : (track == nil ? .needsPreparation : .ready)
            return
        }
        synchronize(lastSnapshot, hostTime: CACurrentMediaTime())
    }

    private func synchronize(_ snapshot: WebPlaybackSnapshot, hostTime: Double) {
        if !snapshot.playing { durationGate.reset() }
        let next: Status
        if !foreground { next = .waiting }
        else if selection == nil { next = .idle }
        else if !enabled { next = .disabled }
        else if snapshot.advertisement { next = .advertisement }
        else if track == nil { next = .needsPreparation }
        else if !snapshot.ready || snapshot.hidden || snapshot.seeking { next = .waiting }
        else if snapshot.buffering { next = .buffering }
        else if snapshot.paused || snapshot.ended { next = .paused }
        else if let track {
            switch durationGate.check(duration: snapshot.duration, expected: track.duration, playing: snapshot.playing, hostTime: hostTime) {
            case .waiting: next = .waiting
            case .different: next = .mismatch
            case .matching: next = renderer.supported ? .playing : .unsupported
            }
        } else { next = .ready }

        if status != next { status = next }
        let playing = next == .playing
        if isSynchronizing != playing { isSynchronizing = playing }
        guard playing, let track else { renderer.stop(); return }
        let latency = bounded(Date().timeIntervalSince1970 - snapshot.sent / 1_000, to: 0...0.35, fallback: 0)
        renderer.synchronize(track: track, position: min(track.duration, snapshot.position + latency * snapshot.rate),
                             playing: true, rate: snapshot.rate, clockPosition: snapshot.position)
        if !historySaved, let selection {
            historySaved = true
            library.saveHistory(selection)
        }
    }

    private func checkFreshness() {
        guard lastSnapshot != nil, CACurrentMediaTime() - lastSampleHost > 0.35 else { return }
        renderer.stop()
        lastSnapshot = nil
        isSynchronizing = false
        videoPlaying = false
        status = selection == nil ? .idle : .waiting
    }
}
