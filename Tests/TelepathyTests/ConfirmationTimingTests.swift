import XCTest

@testable import Telepathy

final class ConfirmationTimingTests: XCTestCase {
  func testQuickPressHasAUsefulMinimumLatch() {
    XCTAssertEqual(ConfirmationTiming.latchInterval(switchDelay: 0), 0.5)
    XCTAssertEqual(ConfirmationTiming.latchInterval(switchDelay: 0.09), 0.5)
  }

  func testQuickPressOutlivesLongConfiguredStabilityDelay() {
    XCTAssertEqual(ConfirmationTiming.latchInterval(switchDelay: 0.65), 0.9)
  }
}
