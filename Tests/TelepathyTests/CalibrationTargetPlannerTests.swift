import CoreGraphics
import XCTest

@testable import Telepathy

final class CalibrationTargetPlannerTests: XCTestCase {
  func testProducesCenterAndFourInsetCorners() {
    let frame = CGRect(x: 100, y: 200, width: 1_000, height: 800)
    let points = CalibrationTargetPlanner.points(in: frame)

    XCTAssertEqual(points.count, 5)
    XCTAssertEqual(points.first, CGPoint(x: 600, y: 600))
    XCTAssertTrue(points.allSatisfy(frame.contains))
    XCTAssertLessThan(points[1].x, frame.midX)
    XCTAssertGreaterThan(points[1].y, frame.midY)
    XCTAssertGreaterThan(points[3].x, frame.midX)
    XCTAssertLessThan(points[3].y, frame.midY)
  }

  func testKeepsTargetsUsableOnSmallScreens() {
    let frame = CGRect(x: 0, y: 0, width: 320, height: 240)
    let points = CalibrationTargetPlanner.points(in: frame)

    XCTAssertTrue(points.allSatisfy(frame.contains))
    for index in points.indices {
      XCTAssertFalse(points.dropFirst(index + 1).contains(points[index]))
    }
  }
}
