import CoreGraphics
import XCTest

@testable import Telepathy

final class HeadDisplayClassifierTests: XCTestCase {
  func testClassifiesDisplaysFromHeadFeaturesWithoutPupils() throws {
    let classifier = HeadDisplayClassifier()
    let bounds = CGRect(x: 0, y: 0, width: 2000, height: 800)
    let displays = [
      ActiveDisplay(id: 1, bounds: CGRect(x: 0, y: 0, width: 1000, height: 800), visibleBounds: CGRect(x: 0, y: 0, width: 1000, height: 760)),
      ActiveDisplay(id: 2, bounds: CGRect(x: 1000, y: 0, width: 1000, height: 800), visibleBounds: CGRect(x: 1000, y: 0, width: 1000, height: 760)),
    ]
    let samples = (0..<8).flatMap { index -> [CalibrationSample] in
      let y = 0.2 + Double(index) * 0.07
      return [
        sample(faceX: 0.42, yaw: -0.25, x: 0.25, y: y),
        sample(faceX: 0.58, yaw: 0.28, x: 0.75, y: y),
      ]
    }
    classifier.fit(samples: samples, desktopBounds: bounds, displays: displays)

    XCTAssertTrue(classifier.isReady)
    let prediction = try XCTUnwrap(classifier.predict(features: features(faceX: 0.60, yaw: 0.30)))
    XCTAssertEqual(prediction.displayID, 2)
    XCTAssertGreaterThan(prediction.confidence, 0.8)
  }

  func testRequiresSamplesForEveryActiveDisplay() {
    let classifier = HeadDisplayClassifier()
    let bounds = CGRect(x: 0, y: 0, width: 3000, height: 800)
    let displays: [ActiveDisplay] = [
      ActiveDisplay(
        id: 1,
        bounds: CGRect(x: 0, y: 0, width: 1000, height: 800),
        visibleBounds: CGRect(x: 0, y: 0, width: 1000, height: 760)
      ),
      ActiveDisplay(
        id: 2,
        bounds: CGRect(x: 1000, y: 0, width: 1000, height: 800),
        visibleBounds: CGRect(x: 1000, y: 0, width: 1000, height: 760)
      ),
      ActiveDisplay(
        id: 3,
        bounds: CGRect(x: 2000, y: 0, width: 1000, height: 800),
        visibleBounds: CGRect(x: 2000, y: 0, width: 1000, height: 760)
      ),
    ]
    let samples = [
      sample(faceX: 0.42, yaw: -0.25, x: 0.15, y: 0.5),
      sample(faceX: 0.58, yaw: 0.28, x: 0.50, y: 0.5),
    ]

    classifier.fit(samples: samples, desktopBounds: bounds, displays: displays)

    XCTAssertFalse(classifier.isReady)
  }

  private func sample(faceX: Double, yaw: Double, x: Double, y: Double) -> CalibrationSample {
    CalibrationSample(features: features(faceX: faceX, yaw: yaw), normalizedX: x, normalizedY: y)
  }

  private func features(faceX: Double, yaw: Double) -> GazeFeatures {
    GazeFeatures(
      timestamp: 1, faceX: faceX, faceY: 0.5, yaw: yaw, pitch: 0,
      pupilX: 0.5, pupilY: 0.5, confidence: 1
    )
  }
}
