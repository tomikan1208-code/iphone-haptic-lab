import SwiftUI

@main
struct HapticLabApp: App {
    @StateObject private var haptics = HapticController()
    @StateObject private var music = MusicPlayback()
    @StateObject private var library: MusicLibrary
    @StateObject private var youtube = YouTubeAccount()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--music-test-library") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("MusicUITestLibrary", isDirectory: true)
            if ProcessInfo.processInfo.arguments.contains("--reset-music-test-library") { try? FileManager.default.removeItem(at: root) }
            _library = StateObject(wrappedValue: MusicLibrary(root: root))
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
