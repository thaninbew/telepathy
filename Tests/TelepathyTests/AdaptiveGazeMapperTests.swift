import CoreGraphics
import XCTest

@testable import Telepathy

final class AdaptiveGazeMapperTests: XCTestCase {
  func testLearnsSyntheticLinearMapping() throws {
    let mapper = AdaptiveGazeMapper()
    let bounds = CGRect(x: -1440, y: 0, width: 4000, height: 1440)

    for index in 0..<24 {
      let x = Double(index % 6) / 5
      let y = Double(index / 6) / 3
      let features = makeFeatures(x: x, y: y, timestamp: Double(index))
      let point = CGPoint(
        x: bounds.minX + (0.1 + 0.8 * x) * bounds.width,
        y: bounds.minY + (0.12 + 0.74 * y) * bounds.height
      )
      mapper.addSample(features: features, point: point, desktopBounds: bounds)
    }

    XCTAssertTrue(mapper.isReady)
    let query = makeFeatures(x: 0.35, y: 0.65, timestamp: 30)
    let prediction = try XCTUnwrap(mapper.predict(features: query, desktopBounds: bounds))
    XCTAssertEqual(prediction.x, bounds.minX + 0.38 * bounds.width, accuracy: 30)
    XCTAssertEqual(prediction.y, bounds.minY + 0.601 * bounds.height, accuracy: 30)
  }

  func testRequiresSpatialCoverage() {
    let mapper = AdaptiveGazeMapper()
    let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    for index in 0..<20 {
      let features = makeFeatures(x: 0.5, y: 0.5, timestamp: Double(index))
      mapper.addSample(
        features: features,
        point: CGPoint(x: 960 + index, y: 540),
        desktopBounds: bounds
      )
    }
    XCTAssertFalse(mapper.isReady)
  }

  func testIntentionalFiveTargetSequenceProducesReadyModel() {
    let mapper = AdaptiveGazeMapper()
    let bounds = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
    let points = CalibrationTargetPlanner.points(in: bounds)
    var samples: [CalibrationSample] = []

    for (index, point) in points.enumerated() {
      let x = Double(point.x / bounds.width)
      let y = Double(point.y / bounds.height)
      for repetition in 0..<2 {
        let features = makeFeatures(
          x: x + Double(repetition) * 0.002,
          y: y + Double(repetition) * 0.002,
          timestamp: Double(index * 2 + repetition)
        )
        samples.append(
          AdaptiveGazeMapper.makeSample(
            features: features,
            point: point,
            desktopBounds: bounds
          )!
        )
      }
    }

    mapper.restore(samples: samples)
    XCTAssertTrue(mapper.isReady)
    XCTAssertEqual(mapper.sampleCount, 10)
  }

  private func makeFeatures(x: Double, y: Double, timestamp: TimeInterval) -> GazeFeatures {
    GazeFeatures(
      timestamp: timestamp,
      faceX: x,
      faceY: y,
      yaw: x - 0.5,
      pitch: y - 0.5,
      pupilX: x,
      pupilY: y,
      confidence: 1
    )
  }
}
