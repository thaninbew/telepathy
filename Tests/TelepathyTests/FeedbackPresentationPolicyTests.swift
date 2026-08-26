import CoreGraphics
import XCTest

@testable import Telepathy

final class FeedbackPresentationPolicyTests: XCTestCase {
  private let policy = FeedbackPresentationPolicy()
  private let displayID: CGDirectDisplayID = 7

  func testSettlingNeverShowsFeedback() {
    let decision = DisplaySwitchDecision(targetDisplayID: displayID, phase: .settling(progress: 0.5))
    XCTAssertNil(
      policy.phase(for: decision, candidateSince: 1, stabilityInterval: 0.09, now: 2)
    )
  }

  func testArmedCueAppearsOnlyAfterStabilityAndThenExpires() {
    let decision = DisplaySwitchDecision(targetDisplayID: displayID, phase: .armed)
    XCTAssertNil(
      policy.phase(for: decision, candidateSince: 1, stabilityInterval: 0.09, now: 1.17)
    )
    XCTAssertEqual(
      policy.phase(for: decision, candidateSince: 1, stabilityInterval: 0.09, now: 1.2),
      .candidate
    )
    XCTAssertNil(
      policy.phase(for: decision, candidateSince: 1, stabilityInterval: 0.09, now: 1.61)
    )
  }

  func testArmedCueStillAppearsAfterLongSwitchDelay() {
    let decision = DisplaySwitchDecision(targetDisplayID: displayID, phase: .armed)
    XCTAssertEqual(
      policy.phase(for: decision, candidateSince: 1, stabilityInterval: 0.65, now: 1.66),
      .candidate
    )
    XCTAssertNil(
      policy.phase(for: decision, candidateSince: 1, stabilityInterval: 0.65, now: 2.08)
    )
  }

  func testDwellProgressWaitsForStableReveal() {
    let decision = DisplaySwitchDecision(targetDisplayID: displayID, phase: .holding(progress: 0.5))
    XCTAssertNil(
      policy.phase(for: decision, candidateSince: 1, stabilityInterval: 0.09, now: 1.17)
    )
    XCTAssertEqual(
      policy.phase(for: decision, candidateSince: 1, stabilityInterval: 0.09, now: 1.2),
      .holding(progress: 0.5)
    )
  }
}
