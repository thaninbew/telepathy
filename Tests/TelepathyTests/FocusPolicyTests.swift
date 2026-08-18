import XCTest

@testable import Telepathy

final class FocusPolicyTests: XCTestCase {
  func testTransfersAfterShortStableLook() {
    var policy = FocusPolicy(
      stabilityInterval: 0.09, mouseQuietInterval: 0.28, switchCooldown: 0.24)
    XCTAssertFalse(
      policy.shouldTransfer(
        to: "side", currentIdentity: "main", now: 1.0, lastPhysicalMouseActivity: 0
      ))
    XCTAssertTrue(
      policy.shouldTransfer(
        to: "side", currentIdentity: "main", now: 1.10, lastPhysicalMouseActivity: 0
      ))
  }

  func testMouseMovementSuppressesTransfer() {
    var policy = FocusPolicy(stabilityInterval: 0.05, mouseQuietInterval: 0.28, switchCooldown: 0)
    _ = policy.shouldTransfer(
      to: "side", currentIdentity: "main", now: 1.0, lastPhysicalMouseActivity: 0.95
    )
    XCTAssertFalse(
      policy.shouldTransfer(
        to: "side", currentIdentity: "main", now: 1.2, lastPhysicalMouseActivity: 1.1
      ))
    XCTAssertTrue(
      policy.shouldTransfer(
        to: "side", currentIdentity: "main", now: 1.4, lastPhysicalMouseActivity: 1.1
      ))
  }

  func testChangingCandidateRestartsStability() {
    var policy = FocusPolicy(stabilityInterval: 0.09, mouseQuietInterval: 0, switchCooldown: 0)
    _ = policy.shouldTransfer(
      to: "left", currentIdentity: "main", now: 1.0, lastPhysicalMouseActivity: 0)
    XCTAssertFalse(
      policy.shouldTransfer(
        to: "right", currentIdentity: "main", now: 1.1, lastPhysicalMouseActivity: 0
      ))
    XCTAssertTrue(
      policy.shouldTransfer(
        to: "right", currentIdentity: "main", now: 1.2, lastPhysicalMouseActivity: 0
      ))
  }
}
