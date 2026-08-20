import XCTest

@testable import Telepathy

final class EdgeBloomMetricsTests: XCTestCase {
  func testCandidateShineIsBroadButSubtle() {
    let metrics = EdgeBloomMetrics.resolve(.candidate)
    XCTAssertEqual(metrics.depth, 24)
    XCTAssertEqual(metrics.opacity, 0.16)
  }

  func testDwellProgressCreepsInWithoutLargeBrightnessJump() {
    let start = EdgeBloomMetrics.resolve(.holding(progress: 0))
    let end = EdgeBloomMetrics.resolve(.holding(progress: 1))
    XCTAssertLessThan(start.depth, end.depth)
    XCTAssertLessThan(start.opacity, end.opacity)
    XCTAssertEqual(end.depth, 52)
    XCTAssertLessThanOrEqual(end.opacity, 0.28)
  }

  func testConfirmedShineCreepsInThenFadesOut() {
    let start = EdgeBloomMetrics.resolve(.confirmed(progress: 0))
    let peak = EdgeBloomMetrics.resolve(.confirmed(progress: 0.24))
    let end = EdgeBloomMetrics.resolve(.confirmed(progress: 1))
    XCTAssertLessThan(start.depth, peak.depth)
    XCTAssertLessThan(peak.depth, end.depth)
    XCTAssertEqual(end.depth, 56)
    XCTAssertEqual(start.opacity, 0)
    XCTAssertEqual(peak.opacity, 0.34)
    XCTAssertEqual(end.opacity, 0)
  }

  func testInputsAreClampedToPhaseRange() {
    XCTAssertEqual(
      EdgeBloomMetrics.resolve(.holding(progress: -1)),
      EdgeBloomMetrics.resolve(.holding(progress: 0))
    )
    XCTAssertEqual(
      EdgeBloomMetrics.resolve(.confirmed(progress: 2)),
      EdgeBloomMetrics.resolve(.confirmed(progress: 1))
    )
  }

  func testShineUsesFiveSmoothInwardStopsWithoutAPerimeterStroke() {
    let spec = EdgeShineGradientSpec.standard
    XCTAssertEqual(spec.locations, [0, 0.08, 0.26, 0.58, 1])
    XCTAssertEqual(spec.locations.count, 5)
    XCTAssertEqual(spec.relativeAlphas.count, 5)
    XCTAssertEqual(spec.relativeAlphas.last, 0)
    XCTAssertGreaterThan(spec.relativeAlphas[1], spec.relativeAlphas[0])
  }

  func testStripPanelsStayNarrowAndNeverOverlapAtCorners() {
    let display = CGRect(x: -2_560, y: 120, width: 2_560, height: 1_440)
    let frames = EdgeStripFrames.resolve(displayFrame: display)
    let strips = [frames.top, frames.bottom, frames.left, frames.right]

    XCTAssertEqual(frames.top.height, EdgeBloomMetrics.maximumDepth)
    XCTAssertEqual(frames.bottom.height, EdgeBloomMetrics.maximumDepth)
    XCTAssertEqual(frames.left.width, EdgeBloomMetrics.maximumDepth)
    XCTAssertEqual(frames.right.width, EdgeBloomMetrics.maximumDepth)

    for firstIndex in strips.indices {
      for secondIndex in strips.indices where secondIndex > firstIndex {
        let overlap = strips[firstIndex].intersection(strips[secondIndex])
        let overlapArea = overlap.isNull ? 0 : overlap.width * overlap.height
        XCTAssertEqual(overlapArea, 0)
      }
    }

    let retainedArea = strips.reduce(0) { $0 + $1.width * $1.height }
    XCTAssertLessThan(retainedArea, display.width * display.height / 8)
  }
}
