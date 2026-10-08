import SwiftUI

@main
struct HapticLabApp: App {
    @UIApplicationDelegateAdaptor(PlayerAppDelegate.self) private var appDelegate
    @StateObject private var presentation = MusicPlayerPresentation.shared
    @StateObject private var haptics = HapticController()
    @StateObject private var music = MusicPlayback()
    @StateObject private var library: MusicLibrary
    @StateObject private var youtube = YouTubeAccount()
    @StateObject private var analysis = AnalysisPreferences()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--music-test-library") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("MusicUITestLibrary", isDirectory: true)
            if ProcessInfo.processInfo.arguments.contains("--reset-music-test-library") { try? FileManager.default.removeItem(at: root) }
            var services = MusicPreparationServices()
            services.analyzeOnPC = { _, selection, file, style, profile, progress in
                if file == nil, ProcessInfo.processInfo.arguments.contains("--music-test-completion") {
                    progress(0.4, "AIが曲の展開を推定しています")
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                    let duration = selection.duration ?? 12
                    return MusicHapticTrack(version: 1, audioSHA256: String(repeating: "a", count: 64), duration: duration,
                        envelope: [0.0, duration].map { .init(time: $0, bass: 0.3, energy: 0.3, sharpness: 0.3) }, taps: [],
                        analysis: .init(engine: "pc", elapsedSeconds: 3, sampleRate: 44_100,
                                        hopMilliseconds: 10, fftSize: 4_096, style: style, profile: profile))
                }
                guard let file else {
                    progress(0.4, "AIが曲の展開を推定しています")
                    try await Task.sleep(nanoseconds: 120_000_000_000)
                    throw MusicError.network("テスト用のPC解析処理です。")
                }
                let source = try await MusicAnalyzer.analyze(file, quality: .precision, progress: progress)
                let info = MusicAnalysisInfo(engine: "pc", elapsedSeconds: 1, sampleRate: 44_100,
                    hopMilliseconds: 10, fftSize: 4_096, style: style, profile: profile)
                let score = MusicArrangementScore(version: 1, sections: [
                    .init(id: "fixture", start: 0, end: source.duration, label: "chorus",
                          confidence: 0.8, mood: "driving", family: "drive")
                ], bars: [], rhythmAgreement: 1, rhythmSource: "all-in-one")
                return MusicHapticTrack(version: 3, audioSHA256: source.audioSHA256, duration: source.duration,
                    envelope: source.envelope.map { point in
                        var point = point; point.intensity = point.energy * 0.25; return point
                    }, taps: source.taps, analysis: info, spectrum: source.spectrum, arrangement: score)
            }
            if ProcessInfo.processInfo.arguments.contains("--music-test-progress") {
                services.youtubeAudioURL = { _ in
                    try await Task.sleep(nanoseconds: 120_000_000_000)
                    throw MusicError.network("テスト用の取得処理です。")
                }
            }
            _library = StateObject(wrappedValue: MusicLibrary(root: root, services: services))
        } else { _library = StateObject(wrappedValue: MusicLibrary()) }
        #else
        _library = StateObject(wrappedValue: MusicLibrary())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(haptics)
                .environmentObject(music)
                .environmentObject(library)
                .environmentObject(youtube)
                .environmentObject(analysis)
                .environmentObject(presentation)
                .tint(LabTheme.mint)
                .preferredColorScheme(.dark)
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--youtube-playback-fixture"),
                       let selection = try? MusicSelection.youtube(id: "lkiV3U0GfGg") {
                        music.load(selection, track: nil, mediaURL: nil, settings: MusicSettings())
                        presentation.expand(orientation: .portrait)
                    }
                    if ProcessInfo.processInfo.arguments.contains("--music-test-library"),
                       ProcessInfo.processInfo.arguments.contains("--music-test-prepared"),
                       library.prepared.isEmpty,
                       let audioURL = Bundle.main.url(forResource: "MusicDemo", withExtension: "wav") {
                        let selection = MusicSelection(id: "music-ui-fixture", kind: .file, title: "Playback Fixture",
                                                       artist: "UI Test", url: "")
                        library.prepare(selection, audioFile: audioURL, method: .device, style: .following, quality: .precision)
                        if ProcessInfo.processInfo.arguments.contains("--music-test-variants") {
                            guard let connection = try? PCServerConnection(address: "http://127.0.0.1:8765", token: String(repeating: "a", count: 32)) else { return }
                            for profile in [MusicArrangement.standard, .orchestral] {
                                let deadline = Date().addingTimeInterval(30)
                                while library.preparation != nil, Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
                                guard library.preparation == nil else { return }
                                library.prepare(selection, audioFile: audioURL, method: .pc, style: .arranged, profile: profile, connection: connection)
                            }
                        }
                    }
                    #endif
                }
                .onChange(of: scenePhase) { phase in
                    if phase != .active {
                        haptics.suspend()
                        music.suspend()
                    }
                    if phase == .background, library.preparation != nil {
                        library.cancelPreparation()
                    }
                }
        }
    }
}
