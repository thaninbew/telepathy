import XCTest

@testable import Telepathy

final class AutoReturnPolicyTests: XCTestCase {
  func testEnabledSwitchPlansReturnToOrigin() {
    var policy = AutoReturnPolicy()
    XCTAssertEqual(
      policy.switched(from: 1, to: 2, enabled: true),
      AutoReturnPlan(originDisplayID: 1, temporaryDisplayID: 2)
    )
  }

  func testPointerActivityAdoptsOnlyTheTemporaryDisplay() {
    var policy = AutoReturnPolicy()
    _ = policy.switched(from: 1, to: 2, enabled: true)
    XCTAssertFalse(policy.pointerActivity(on: 1))
    XCTAssertNotNil(policy.plan)
    XCTAssertTrue(policy.pointerActivity(on: 2))
    XCTAssertNil(policy.plan)
  }

  func testReturnSuppressesImmediateBounceUntilPredictionLeavesTemporaryDisplay() {
    var policy = AutoReturnPolicy()
    let plan = policy.switched(from: 1, to: 2, enabled: true)!
    XCTAssertEqual(policy.fire(plan), 1)
    XCTAssertTrue(policy.shouldSuppress(2))
    XCTAssertFalse(policy.shouldSuppress(1))
    XCTAssertFalse(policy.shouldSuppress(2))
  }

  func testManualReturnDoesNotScheduleBounceBack() {
    var policy = AutoReturnPolicy()
    _ = policy.switched(from: 1, to: 2, enabled: true)
    XCTAssertNil(policy.switched(from: 2, to: 1, enabled: true))
    XCTAssertNil(policy.plan)
  }
}
