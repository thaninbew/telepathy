import CoreGraphics
import XCTest

@testable import Telepathy

final class GazeIndicatorSmootherTests: XCTestCase {
  func testStartsAtFirstSampleAndSoftensLaterMovement() {
    var smoother = GazeIndicatorSmoother(newSampleWeight: 0.2)

    XCTAssertEqual(smoother.update(with: CGPoint(x: 100, y: 50)), CGPoint(x: 100, y: 50))
    XCTAssertEqual(smoother.update(with: CGPoint(x: 200, y: 150)), CGPoint(x: 120, y: 70))
  }

  func testResetStartsFresh() {
    var smoother = GazeIndicatorSmoother(newSampleWeight: 0.2)
    _ = smoother.update(with: CGPoint(x: 100, y: 50))
    smoother.reset()

    XCTAssertEqual(smoother.update(with: CGPoint(x: 300, y: 200)), CGPoint(x: 300, y: 200))
  }
}
