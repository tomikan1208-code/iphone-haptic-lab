import SwiftUI

@main
struct ResonWebApp: App {
    @StateObject private var browser = YouTubeBrowser()
    var body: some Scene {
        WindowGroup {
            BrowserScreen().environmentObject(browser)
                .preferredColorScheme(.dark).tint(WebTheme.mint)
        }
    }
}
