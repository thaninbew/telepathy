import XCTest

@testable import Telepathy

final class CameraRuntimePolicyTests: XCTestCase {
  func testOffAndSuspendedAlwaysStopCapture() {
    XCTAssertFalse(
      shouldRun(enabled: false, trusted: true, calibrating: true, debug: true, displays: 2))
    XCTAssertFalse(
      CameraRuntimePolicy.shouldRun(
        enabled: true,
        accessibilityTrusted: true,
        suspended: true,
        isCalibrating: true,
        experimentalIndicatorEnabled: true,
        displayCount: 2
      )
    )
  }

  func testNormalCaptureRequiresTrustAndTwoDisplays() {
    XCTAssertFalse(shouldRun(enabled: true, trusted: false, displays: 2))
    XCTAssertFalse(shouldRun(enabled: true, trusted: true, displays: 1))
    XCTAssertTrue(shouldRun(enabled: true, trusted: true, displays: 2))
  }

  func testExplicitResearchModesCanRunOnOneDisplay() {
    XCTAssertTrue(shouldRun(enabled: true, trusted: false, calibrating: true, displays: 1))
    XCTAssertTrue(shouldRun(enabled: true, trusted: false, debug: true, displays: 1))
  }

  func testOnlyCalibrationAndExperimentalIndicatorNeedDetailedVision() {
    XCTAssertEqual(
      CameraRuntimePolicy.processingDetail(
        isCalibrating: false,
        experimentalIndicatorEnabled: false
      ),
      .headOnly
    )
    XCTAssertEqual(
      CameraRuntimePolicy.processingDetail(
        isCalibrating: true,
        experimentalIndicatorEnabled: false
      ),
      .detailed
    )
  }

  func testWakeDoesNotResumeWhileSessionRemainsInactive() {
    var state = RuntimeSuspensionState()
    state.screenSleeping = true
    state.sessionInactive = true
    state.screenSleeping = false
    XCTAssertTrue(state.isSuspended)
    state.sessionInactive = false
    XCTAssertFalse(state.isSuspended)
  }

  func testQueuedFeaturesAreRejectedAfterSuspensionStopsCamera() {
    XCTAssertTrue(
      CameraRuntimePolicy.shouldConsumeFeatures(cameraWanted: true, suspended: false)
    )
    XCTAssertFalse(
      CameraRuntimePolicy.shouldConsumeFeatures(cameraWanted: false, suspended: true)
    )
  }

  private func shouldRun(
    enabled: Bool,
    trusted: Bool,
    calibrating: Bool = false,
    debug: Bool = false,
    displays: Int
  ) -> Bool {
    CameraRuntimePolicy.shouldRun(
      enabled: enabled,
      accessibilityTrusted: trusted,
      suspended: false,
      isCalibrating: calibrating,
      experimentalIndicatorEnabled: debug,
      displayCount: displays
    )
  }
}
