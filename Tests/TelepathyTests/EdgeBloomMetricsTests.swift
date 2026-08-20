import XCTest

@testable import Telepathy

final class EdgeBloomMetricsTests: XCTestCase {
  func testCandidateBloomIsThinAndFaint() {
    let metrics = EdgeBloomMetrics.resolve(.candidate)
    XCTAssertEqual(metrics.depth, 6)
    XCTAssertLessThanOrEqual(metrics.edgeAlpha, 0.055)
    XCTAssertLessThanOrEqual(metrics.hairlineAlpha, 0.07)
  }

  func testDwellProgressGrowsWithoutLargeBrightnessJump() {
    let start = EdgeBloomMetrics.resolve(.holding(progress: 0))
    let end = EdgeBloomMetrics.resolve(.holding(progress: 1))
    XCTAssertLessThan(start.depth, end.depth)
    XCTAssertLessThan(start.edgeAlpha, end.edgeAlpha)
    XCTAssertLessThanOrEqual(end.edgeAlpha, 0.095)
  }

  func testConfirmedBloomCreepsInThenFadesOut() {
    let start = EdgeBloomMetrics.resolve(.confirmed(progress: 0))
    let peak = EdgeBloomMetrics.resolve(.confirmed(progress: 0.28))
    let end = EdgeBloomMetrics.resolve(.confirmed(progress: 1))
    XCTAssertLessThan(start.depth, peak.depth)
    XCTAssertLessThan(peak.depth, end.depth)
    XCTAssertEqual(start.edgeAlpha, 0)
    XCTAssertGreaterThan(peak.edgeAlpha, 0)
    XCTAssertEqual(end.edgeAlpha, 0)
    XCTAssertEqual(end.middleAlpha, 0)
    XCTAssertEqual(end.hairlineAlpha, 0)
  }
}
