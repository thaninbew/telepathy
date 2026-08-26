import CoreGraphics
import XCTest

@testable import Telepathy

final class CalibrationValidatorTests: XCTestCase {
  private let bounds = CGRect(x: 0, y: 0, width: 2_000, height: 1_000)
  private let displays = [
    ActiveDisplay(
      id: 1,
      bounds: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
      visibleBounds: CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
    ),
    ActiveDisplay(
      id: 2,
      bounds: CGRect(x: 1_000, y: 0, width: 1_000, height: 1_000),
      visibleBounds: CGRect(x: 1_000, y: 0, width: 1_000, height: 1_000)
    ),
  ]

  func testPassesHeldOutSamplesThatMatchLearnedDisplays() {
    let result = CalibrationValidator.evaluate(
      trainingSamples: trainingSamples(),
      observations: observations(swapped: false),
      desktopBounds: bounds,
      displays: displays
    )

    XCTAssertTrue(result.passed)
    XCTAssertEqual(result.overallAccuracy, 1)
    XCTAssertEqual(result.accuracyByDisplay[1], 1)
    XCTAssertEqual(result.accuracyByDisplay[2], 1)
  }

  func testRejectsHeldOutSamplesThatResolveToWrongDisplays() {
    let result = CalibrationValidator.evaluate(
      trainingSamples: trainingSamples(),
      observations: observations(swapped: true),
      desktopBounds: bounds,
      displays: displays
    )

    XCTAssertFalse(result.passed)
    XCTAssertEqual(result.overallAccuracy, 0)
  }

  func testSingleDisplayDoesNotRequireClassifierValidation() {
    let result = CalibrationValidator.evaluate(
      trainingSamples: [],
      observations: [],
      desktopBounds: CGRect(x: 0, y: 0, width: 1_000, height: 1_000),
      displays: [displays[0]]
    )

    XCTAssertTrue(result.passed)
  }

  private func trainingSamples() -> [CalibrationSample] {
    (0..<12).flatMap { index -> [CalibrationSample] in
      let variation = Double(index - 6) * 0.003
      return [
        sample(displayID: 1, faceX: 0.32 + variation, yaw: -0.22 + variation),
        sample(displayID: 2, faceX: 0.68 + variation, yaw: 0.22 + variation),
      ]
    }
  }

  private func observations(swapped: Bool) -> [CalibrationValidationObservation] {
    (0..<5).flatMap { index -> [CalibrationValidationObservation] in
      let variation = Double(index - 2) * 0.002
      let left = features(faceX: 0.32 + variation, yaw: -0.22 + variation)
      let right = features(faceX: 0.68 + variation, yaw: 0.22 + variation)
      return [
        CalibrationValidationObservation(
          expectedDisplayID: 1,
          features: swapped ? right : left
        ),
        CalibrationValidationObservation(
          expectedDisplayID: 2,
          features: swapped ? left : right
        ),
      ]
    }
  }

  private func sample(
    displayID: CGDirectDisplayID,
    faceX: Double,
    yaw: Double
  ) -> CalibrationSample {
    let point =
      displayID == 1
      ? CGPoint(x: 500, y: 500)
      : CGPoint(x: 1_500, y: 500)
    return AdaptiveGazeMapper.makeSample(
      features: features(faceX: faceX, yaw: yaw),
      point: point,
      desktopBounds: bounds
    )!
  }

  private func features(faceX: Double, yaw: Double) -> GazeFeatures {
    GazeFeatures(
      timestamp: faceX,
      faceX: faceX,
      faceY: 0.5,
      yaw: yaw,
      pitch: 0,
      pupilX: 0.5,
      pupilY: 0.5,
      confidence: 1
    )
  }
}
