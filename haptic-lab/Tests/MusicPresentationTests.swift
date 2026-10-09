import XCTest
import UIKit
@testable import HapticLab

final class MusicPresentationTests: XCTestCase {
    @MainActor
    func testCollapseFollowsTheFingerWithoutCommittingUntilRelease() throws {
        var requests: [UIInterfaceOrientationMask] = []
        let presentation = MusicPlayerPresentation(observeDevice: false) { requests.append($0) }
        presentation.expand(orientation: .portrait)
        presentation.updateDrag(translation: CGSize(width: 0, height: 50), distance: 400)
        XCTAssertEqual(try XCTUnwrap(presentation.drag).progress, 0.125)
        presentation.updateDrag(translation: CGSize(width: 0, height: 100), distance: 200)
        let drag = try XCTUnwrap(presentation.drag)
        XCTAssertEqual(drag.distance, 400, "The distance must stay fixed as the player shrinks")
        XCTAssertEqual(drag.interpolate(0, 400), 100)
        XCTAssertEqual(presentation.mode, .portrait)
        XCTAssertTrue(requests.isEmpty)
        presentation.endDrag(predictedTranslation: CGSize(width: 0, height: 100))
        XCTAssertEqual(presentation.mode, .minimized)
        XCTAssertNil(presentation.drag)
        XCTAssertTrue(requests.isEmpty)
    }

    @MainActor
    func testOrientationChangesOnlyAfterReleaseAndShortReturnRestoresFullScreen() {
        var requests: [UIInterfaceOrientationMask] = []
        let presentation = MusicPlayerPresentation(observeDevice: false) { requests.append($0) }
        presentation.expand(orientation: .portrait)
        presentation.updateDrag(translation: CGSize(width: 0, height: -100), distance: 300)
        presentation.deviceRotated(.landscapeLeft)
        XCTAssertEqual(presentation.mode, .portrait)
        XCTAssertTrue(requests.isEmpty)
        presentation.endDrag(predictedTranslation: CGSize(width: 0, height: -100))
        XCTAssertEqual(presentation.mode, .landscape)
        XCTAssertEqual(requests, [.landscape])
        presentation.updateDrag(translation: CGSize(width: 0, height: 25), distance: 200)
        presentation.endDrag(predictedTranslation: CGSize(width: 0, height: 25))
        XCTAssertEqual(presentation.mode, .landscape)
        XCTAssertNil(presentation.drag)
        XCTAssertEqual(requests, [.landscape])
    }

    @MainActor
    func testSeekingReversingAndCancellingCannotChangePresentation() {
        let presentation = MusicPlayerPresentation(observeDevice: false) { _ in }
        presentation.expand(orientation: .portrait)
        presentation.updateDrag(translation: CGSize(width: 120, height: 30), distance: 300)
        XCTAssertNil(presentation.drag)
        presentation.updateDrag(translation: CGSize(width: 0, height: -50), distance: 300)
        presentation.updateDrag(translation: CGSize(width: 0, height: 50), distance: 300)
        XCTAssertEqual(presentation.drag?.progress, 0)
        presentation.endDrag(predictedTranslation: CGSize(width: 0, height: 150))
        XCTAssertEqual(presentation.mode, .portrait)
        presentation.updateDrag(translation: CGSize(width: 0, height: 100), distance: 400)
        presentation.cancelDrag()
        presentation.endDrag(predictedTranslation: CGSize(width: 0, height: 300))
        XCTAssertEqual(presentation.mode, .portrait)
        XCTAssertNil(presentation.drag)
    }

    @MainActor
    func testFastUpwardFlingExpandsTheMiniPlayerButTinyMovementDoesNot() {
        let presentation = MusicPlayerPresentation(observeDevice: false) { _ in }
        presentation.updateDrag(translation: CGSize(width: 0, height: -12), distance: 400)
        presentation.endDrag(predictedTranslation: CGSize(width: 0, height: -300))
        XCTAssertEqual(presentation.mode, .minimized)
        presentation.updateDrag(translation: CGSize(width: 0, height: -30), distance: 400)
        presentation.endDrag(predictedTranslation: CGSize(width: 0, height: -300))
        XCTAssertEqual(presentation.mode, .portrait)
        XCTAssertNil(presentation.drag)
    }

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
