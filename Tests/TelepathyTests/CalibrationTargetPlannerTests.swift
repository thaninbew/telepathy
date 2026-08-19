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

  func testFullCalibrationAddsPostureAndPerimeterCoverage() {
    let frame = CGRect(x: -1_440, y: 80, width: 1_440, height: 900)
    let targets = CalibrationTargetPlanner.fullTrainingTargets(in: frame)

    XCTAssertEqual(targets.count, 9)
    XCTAssertEqual(targets.first?.purpose, .posture)
    XCTAssertEqual(targets.first?.point, CGPoint(x: -720, y: 530))
    XCTAssertEqual(targets.dropFirst().map(\.purpose), Array(repeating: .coverage, count: 8))
    XCTAssertTrue(targets.allSatisfy { frame.contains($0.point) })
    for index in targets.indices {
      XCTAssertFalse(targets.dropFirst(index + 1).contains { $0.point == targets[index].point })
    }
  }

  func testValidationTargetsAreHeldOutFromTraining() {
    let frame = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
    let training = CalibrationTargetPlanner.fullTrainingTargets(in: frame).map(\.point)
    let validation = CalibrationTargetPlanner.validationTargets(in: frame)

    XCTAssertEqual(validation.count, 2)
    XCTAssertTrue(validation.allSatisfy { $0.purpose == .validation })
    XCTAssertTrue(validation.allSatisfy { frame.contains($0.point) })
    XCTAssertTrue(
      validation.allSatisfy { target in
        !training.contains { $0 == target.point }
      })
  }
}
