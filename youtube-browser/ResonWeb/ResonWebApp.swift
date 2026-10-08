import SwiftUI

@main
@MainActor
struct ResonWebApp: App {
    @StateObject private var browser: YouTubeBrowser
    @StateObject private var library: MusicLibrary
    @StateObject private var preferences: AnalysisPreferences
    @StateObject private var haptics: BrowserHaptics

    init() {
        let browser = YouTubeBrowser()
        #if DEBUG
        let library = BrowserFixtures.makeLibrary()
        #else
        let library = MusicLibrary()
        #endif
        let haptics = BrowserHaptics(library: library)
        haptics.attach(to: browser)
        _browser = StateObject(wrappedValue: browser)
        _library = StateObject(wrappedValue: library)
        _preferences = StateObject(wrappedValue: AnalysisPreferences())
        _haptics = StateObject(wrappedValue: haptics)
    }
    var body: some Scene {
        WindowGroup {
            BrowserScreen().environmentObject(browser).environmentObject(library)
                .environmentObject(preferences).environmentObject(haptics)
                .preferredColorScheme(.dark).tint(WebTheme.mint)
        }
    }
}
