import CoreHaptics
import XCTest
@testable import HapticLab

final class HapticAHAPTests: XCTestCase {
    @MainActor
    func testOverlappingTextureClickAndDynamicCurvesRoundTripThroughNativeAHAP() throws {
        let source = HapticPatternSpec(id: "layered", name: "Texture + click", subtitle: "", symbol: "waveform",
            category: "texture", duration: 2, events: [
                .init(kind: .continuous, time: 0, duration: 2, intensity: 0.6, sharpness: 0.3),
                .init(kind: .tap, time: 0.8, duration: 0, intensity: 0.9, sharpness: 1)
            ], curves: [.init(parameter: .sharpness, points: [
                .init(time: 0.4, value: -0.2), .init(time: 1.4, value: 0.4)
            ])], dynamicParameters: [.init(parameter: .intensity, time: 0.2, value: 0.7)])
        let data = try HapticAHAP.encode(source)
        let document = try HapticAHAP(data: data)
        XCTAssertEqual(document.duration, 2)
        XCTAssertFalse(document.containsAudio)
        XCTAssertEqual(try document.pattern().duration, 2, accuracy: 0.001)
        XCTAssertNoThrow(try MusicHapticRenderer.makePattern(source))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try XCTUnwrap(root["Pattern"] as? [[String: Any]])
        let curve = try XCTUnwrap(entries.compactMap { $0["ParameterCurve"] as? [String: Any] }.first)
        let points = try XCTUnwrap(curve["ParameterCurveControlPoints"] as? [[String: Any]])
        XCTAssertEqual(curve["Time"] as? Double, 0.4)
        XCTAssertEqual(points.last?["Time"] as? Double ?? -1, 1, accuracy: 0.000001)
        XCTAssertEqual(entries.filter { $0["Parameter"] != nil }.count, 1)
    }

    func testAudioContinuousAndHapticsShareTheAHAPTimeline() throws {
        let data = Data("""
        {"Version":1,"Pattern":[
          {"Event":{"Time":0,"EventType":"AudioContinuous","EventDuration":1}},
          {"Event":{"Time":0.5,"EventType":"HapticTransient"}}
        ]}
        """.utf8)
        let document = try HapticAHAP(data: data)
        XCTAssertTrue(document.containsAudio)
        XCTAssertNoThrow(try document.pattern())
    }

    func testRejectsBooleanTimesAmbiguousEntriesAndExternalAudioAssets() {
        for content in [
            "{\"Version\":true,\"Pattern\":[{\"Event\":{\"Time\":0,\"EventType\":\"HapticTransient\"}}]}",
            "{\"Version\":1,\"Pattern\":[{\"Event\":{\"Time\":true,\"EventType\":\"HapticTransient\"}}]}",
            "{\"Version\":1,\"Pattern\":[{\"Event\":{\"Time\":0,\"EventType\":\"HapticTransient\"},\"Parameter\":{}}]}",
            "{\"Version\":1,\"Pattern\":[{\"Event\":{\"Time\":0,\"EventType\":\"AudioCustom\",\"EventWaveformPath\":\"../audio.wav\"}}]}"
        ] { XCTAssertThrowsError(try HapticAHAP(data: Data(content.utf8))) }
    }
}
