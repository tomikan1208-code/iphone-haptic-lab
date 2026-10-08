import SwiftUI

@main
@MainActor
struct ResonWebApp: App {
    // StateObject creates the session when SwiftUI installs it, after app startup.
    // Keep WebKit creation inside this autoclosure, rather than eagerly in App.init.
    @StateObject private var session = ResonWebSession()

    var body: some Scene {
        WindowGroup {
            BrowserScreen().environmentObject(session.browser).environmentObject(session.library)
                .environmentObject(session.preferences).environmentObject(session.haptics)
                .preferredColorScheme(.dark).tint(WebTheme.mint)
        }
    }
}

@MainActor
private final class ResonWebSession: ObservableObject {
    let browser: YouTubeBrowser
    let library: MusicLibrary
    let preferences: AnalysisPreferences
    let haptics: BrowserHaptics

    init() {
        browser = YouTubeBrowser()
        #if DEBUG
        library = BrowserFixtures.makeLibrary()
        #else
        library = MusicLibrary()
        #endif
        preferences = AnalysisPreferences()
        haptics = BrowserHaptics(library: library)
        haptics.attach(to: browser)
    }
}
