struct CameraRuntimePolicy {
  static func shouldRun(
    enabled: Bool,
    accessibilityTrusted: Bool,
    suspended: Bool,
    isCalibrating: Bool,
    experimentalIndicatorEnabled: Bool,
    displayCount: Int
  ) -> Bool {
    guard enabled, !suspended else { return false }
    if isCalibrating || experimentalIndicatorEnabled { return true }
    return accessibilityTrusted && displayCount >= 2
  }

  static func processingDetail(
    isCalibrating: Bool,
    experimentalIndicatorEnabled: Bool
  ) -> CameraGazeTracker.ProcessingDetail {
    isCalibrating || experimentalIndicatorEnabled ? .detailed : .headOnly
  }

  static func shouldConsumeFeatures(cameraWanted: Bool, suspended: Bool) -> Bool {
    cameraWanted && !suspended
  }
}

struct RuntimeSuspensionState: Equatable {
  var screenSleeping = false
  var sessionInactive = false

  var isSuspended: Bool {
    screenSleeping || sessionInactive
  }
}
