import XCTest

@testable import Telepathy

final class DisplaySwitchPolicyTests: XCTestCase {
  func testNeverActsWithinCurrentDisplay() {
    var policy = DisplaySwitchPolicy()
    let decision = policy.evaluate(
      targetDisplayID: 1,
      currentDisplayID: 1,
      mode: .automatic,
      now: 1,
      lastPhysicalMouseActivity: 0
    )
    XCTAssertEqual(decision.phase, .idle)
    XCTAssertNil(policy.candidateDisplayID)
  }

  func testAutomaticCommitsAfterStableHeadTurn() {
    var policy = DisplaySwitchPolicy(
      stabilityInterval: 0.09,
      holdInterval: 0.65,
      mouseQuietInterval: 0,
      switchCooldown: 0
    )
    XCTAssertEqual(
      policy.evaluate(
        targetDisplayID: 2, currentDisplayID: 1, mode: .automatic,
        now: 1, lastPhysicalMouseActivity: 0
      ).phase,
      .settling(progress: 0)
    )
    XCTAssertEqual(
      policy.evaluate(
        targetDisplayID: 2, currentDisplayID: 1, mode: .automatic,
        now: 1.1, lastPhysicalMouseActivity: 0
      ).phase,
      .commit
    )
  }

  func testHoldReportsProgressBeforeCommit() {
    var policy = DisplaySwitchPolicy(
      stabilityInterval: 0.05,
      holdInterval: 0.5,
      mouseQuietInterval: 0,
      switchCooldown: 0
    )
    _ = policy.evaluate(
      targetDisplayID: 2, currentDisplayID: 1, mode: .hold,
      now: 1, lastPhysicalMouseActivity: 0
    )
    let halfway = policy.evaluate(
      targetDisplayID: 2, currentDisplayID: 1, mode: .hold,
      now: 1.25, lastPhysicalMouseActivity: 0
    )
    XCTAssertEqual(halfway.phase, .holding(progress: 0.5))
    XCTAssertEqual(
      policy.evaluate(
        targetDisplayID: 2, currentDisplayID: 1, mode: .hold,
        now: 1.5, lastPhysicalMouseActivity: 0
      ).phase,
      .commit
    )
  }

  func testExpressionOnlyCommitsMatchingArmedSignal() {
    var policy = DisplaySwitchPolicy(
      stabilityInterval: 0.05,
      holdInterval: 0.5,
      mouseQuietInterval: 0,
      switchCooldown: 0
    )
    _ = policy.evaluate(
      targetDisplayID: 2, currentDisplayID: 1, mode: .wink,
      now: 1, lastPhysicalMouseActivity: 0
    )
    XCTAssertEqual(
      policy.evaluate(
        targetDisplayID: 2, currentDisplayID: 1, mode: .wink,
        now: 1.1, lastPhysicalMouseActivity: 0, signal: .mouthOpen
      ).phase,
      .armed
    )
    XCTAssertEqual(
      policy.evaluate(
        targetDisplayID: 2, currentDisplayID: 1, mode: .wink,
        now: 1.2, lastPhysicalMouseActivity: 0, signal: .wink
      ).phase,
      .commit
    )
  }

  func testMiddleMouseConfirmationOverridesItsOwnQuietPeriod() {
    var policy = DisplaySwitchPolicy(
      stabilityInterval: 0.05,
      holdInterval: 0.5,
      mouseQuietInterval: 0.28,
      switchCooldown: 0
    )
    _ = policy.evaluate(
      targetDisplayID: 2, currentDisplayID: 1, mode: .mouse,
      now: 1, lastPhysicalMouseActivity: 0
    )
    XCTAssertEqual(
      policy.evaluate(
        targetDisplayID: 2, currentDisplayID: 1, mode: .mouse,
        now: 1.1, lastPhysicalMouseActivity: 1.1, signal: .mouse
      ).phase,
      .commit
    )
  }
}
