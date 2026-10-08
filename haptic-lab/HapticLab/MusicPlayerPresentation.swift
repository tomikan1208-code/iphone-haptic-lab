import SwiftUI
import UIKit

/// Keeps presentation separate from playback. Resizing the player never reloads its media.
@MainActor
final class MusicPlayerPresentation: ObservableObject {
    enum Mode: Equatable { case minimized, portrait, landscape }
    static let shared = MusicPlayerPresentation()
    @Published private(set) var mode: Mode = .minimized
    var isExpanded: Bool { mode != .minimized }
    var supportedOrientations: UIInterfaceOrientationMask { mode == .landscape ? .landscape : .portrait }
    private var orientationObserver: NSObjectProtocol?
    private let requestOrientation: (UIInterfaceOrientationMask) -> Void

    init(observeDevice: Bool = true, requestOrientation: ((UIInterfaceOrientationMask) -> Void)? = nil) {
        self.requestOrientation = requestOrientation ?? { MusicPlayerPresentation.rotateScene($0) }
        if observeDevice {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            orientationObserver = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.deviceRotated(UIDevice.current.orientation) }
            }
        }
    }

    deinit {
        if let orientationObserver { NotificationCenter.default.removeObserver(orientationObserver) }
    }

    func expand(orientation: UIDeviceOrientation? = nil) {
        setMode((orientation ?? UIDevice.current.orientation).isLandscape ? .landscape : .portrait)
    }
    func minimize() { setMode(.minimized) }
    func enterLandscape() { setMode(.landscape) }
    func returnToPortrait() { setMode(.portrait) }

    func deviceRotated(_ orientation: UIDeviceOrientation) {
        guard isExpanded else { return }
        if orientation.isLandscape { enterLandscape() }
        else if orientation == .portrait || orientation == .portraitUpsideDown { returnToPortrait() }
    }

    func swipe(up: Bool) {
        switch mode {
        case .minimized: if up { expand() }
        case .portrait: if up { enterLandscape() } else { minimize() }
        case .landscape: if !up { returnToPortrait() }
        }
    }

    private func setMode(_ next: Mode) {
        guard mode != next else { return }
        let previousOrientations = supportedOrientations
        mode = next
        if supportedOrientations != previousOrientations { requestOrientation(supportedOrientations) }
    }

    static func rotateScene(_ orientations: UIInterfaceOrientationMask) {
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }) else { return }
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { _ in }
        }
    }
}

final class PlayerAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MusicPlayerPresentation.shared.supportedOrientations
    }
}
