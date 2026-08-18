import XCTest

@testable import Telepathy

final class ExpressionConfirmationDetectorTests: XCTestCase {
  func testDetectsWinkButNotBilateralBlink() {
    var detector = ExpressionConfirmationDetector()
    for _ in 0..<20 {
      XCTAssertEqual(detector.update(features: features(left: 0.30, right: 0.30, mouth: 0.05), learnNeutral: true), .none)
    }
    XCTAssertEqual(
      detector.update(features: features(left: 0.09, right: 0.29, mouth: 0.05), learnNeutral: false),
      .wink
    )
    XCTAssertEqual(
      detector.update(features: features(left: 0.08, right: 0.08, mouth: 0.05), learnNeutral: false),
      .none
    )
  }

  func testMouthOpenIsEdgeTriggered() {
    var detector = ExpressionConfirmationDetector()
    for _ in 0..<20 {
      _ = detector.update(features: features(left: 0.3, right: 0.3, mouth: 0.05), learnNeutral: true)
    }
    let open = features(left: 0.3, right: 0.3, mouth: 0.16)
    XCTAssertEqual(detector.update(features: open, learnNeutral: false), .mouthOpen)
    XCTAssertEqual(detector.update(features: open, learnNeutral: false), .none)
  }

  private func features(left: Double, right: Double, mouth: Double) -> GazeFeatures {
    var value = GazeFeatures(
      timestamp: 1, faceX: 0.5, faceY: 0.5, yaw: 0, pitch: 0,
      pupilX: 0.5, pupilY: 0.5, confidence: 1
    )
    value.leftEyeOpenness = left
    value.rightEyeOpenness = right
    value.mouthOpenness = mouth
    return value
  }
}
