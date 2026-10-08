import XCTest
import UIKit
@testable import HapticLab

final class MusicPresentationTests: XCTestCase {
    @MainActor
    func testCorrectedSwipesEnterLandscapeReturnToPortraitThenMinimize() {
        var requests: [UIInterfaceOrientationMask] = []
        let presentation = MusicPlayerPresentation(observeDevice: false) { requests.append($0) }
        presentation.expand(orientation: .portrait)
        presentation.swipe(up: true)
        XCTAssertEqual(presentation.mode, .landscape)
        presentation.swipe(up: false)
        XCTAssertEqual(presentation.mode, .portrait)
        presentation.swipe(up: false)
        XCTAssertEqual(presentation.mode, .minimized)
        XCTAssertEqual(requests, [.landscape, .portrait])
    }

    @MainActor
    func testPhysicalRotationOnlyExpandsAnAlreadyOpenPlayerAndIgnoresFlatDevice() {
        let presentation = MusicPlayerPresentation(observeDevice: false) { _ in }
        presentation.deviceRotated(.landscapeLeft)
        XCTAssertEqual(presentation.mode, .minimized)
        presentation.expand(orientation: .landscapeRight)
        XCTAssertEqual(presentation.mode, .landscape)
        presentation.deviceRotated(.faceUp)
        XCTAssertEqual(presentation.mode, .landscape)
        presentation.deviceRotated(.portrait)
        XCTAssertEqual(presentation.mode, .portrait)
        presentation.deviceRotated(.landscapeLeft)
        XCTAssertEqual(presentation.mode, .landscape)
        presentation.minimize()
        presentation.deviceRotated(.landscapeRight)
        XCTAssertEqual(presentation.mode, .minimized)
    }
}
