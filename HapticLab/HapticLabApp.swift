import SwiftUI

@main
struct HapticLabApp: App {
    @StateObject private var haptics = HapticController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(haptics)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { phase in
                    if phase != .active {
                        haptics.suspend()
                    }
                }
        }
    }
}

