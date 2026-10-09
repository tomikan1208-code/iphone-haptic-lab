import SwiftUI
import UIKit

/// Keeps presentation separate from playback. Resizing the player never reloads its media.
@MainActor
final class MusicPlayerPresentation: ObservableObject {
    enum Mode: Equatable { case minimized, portrait, landscape }
    static let shared = MusicPlayerPresentation()
    @Published private(set) var mode: Mode = .minimized
    @Published private(set) var drag: MusicPlayerDrag?
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
        guard isExpanded, drag == nil else { return }
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

    func updateDrag(translation: CGSize, distance: CGFloat) {
        guard translation.width.isFinite, translation.height.isFinite, distance.isFinite else { return }
        if drag == nil {
            guard abs(translation.height) >= 10,
                  abs(translation.height) > abs(translation.width) * 1.35,
                  let target = MusicPlayerDrag.target(from: mode, up: translation.height < 0) else { return }
            drag = MusicPlayerDrag(source: mode, target: target, distance: max(100, distance))
        }
        drag?.update(translation: translation.height)
    }

    func endDrag(predictedTranslation: CGSize) {
        guard let drag else { return }
        let commit = drag.shouldComplete(predictedTranslation: predictedTranslation.height)
        self.drag = nil
        if commit { setMode(drag.target) }
    }

    func cancelDrag() { drag = nil }

    private func setMode(_ next: Mode) {
        drag = nil
        guard mode != next else { return }
        let previousOrientations = supportedOrientations
        withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) { mode = next }
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

/// The destination is locked on the first vertical movement; presentation only
/// commits after release. Horizontal seeking never starts a presentation drag.
struct MusicPlayerDrag: Equatable {
    let source: MusicPlayerPresentation.Mode
    let target: MusicPlayerPresentation.Mode
    let distance: CGFloat
    private(set) var translation: CGFloat = 0
    var up: Bool { target == .landscape || source == .minimized }
    var progress: CGFloat { min(1, abs(translation) / distance) }

    static func target(from source: MusicPlayerPresentation.Mode, up: Bool) -> MusicPlayerPresentation.Mode? {
        switch source {
        case .minimized: return up ? .portrait : nil
        case .portrait: return up ? .landscape : .minimized
        case .landscape: return up ? nil : .portrait
        }
    }

    mutating func update(translation: CGFloat) {
        self.translation = up ? min(0, max(-distance, translation)) : max(0, min(distance, translation))
    }

    func shouldComplete(predictedTranslation: CGFloat) -> Bool {
        guard abs(translation) >= 18, predictedTranslation.isFinite else { return false }
        let projected = up ? max(0, -predictedTranslation) : max(0, predictedTranslation)
        let threshold = min(110, max(44, distance * 0.22))
        return abs(translation) >= threshold || projected >= threshold * 1.5
    }

    func interpolate(_ sourceValue: CGFloat, _ targetValue: CGFloat) -> CGFloat {
        sourceValue + (targetValue - sourceValue) * progress
    }
}

final class PlayerAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MusicPlayerPresentation.shared.supportedOrientations
    }
}
