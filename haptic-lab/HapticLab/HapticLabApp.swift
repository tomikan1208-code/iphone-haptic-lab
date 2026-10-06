import SwiftUI

@main
struct HapticLabApp: App {
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
                .tint(LabTheme.mint)
                .preferredColorScheme(.dark)
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
