import Foundation

struct ExpressionConfirmationDetector {
  private var neutralLeftEye: Double?
  private var neutralRightEye: Double?
  private var neutralMouth: Double?
  private var winkWasActive = false
  private var mouthWasActive = false

  mutating func update(features: GazeFeatures, learnNeutral: Bool) -> ConfirmationSignal {
    guard let left = features.leftEyeOpenness,
      let right = features.rightEyeOpenness,
      let mouth = features.mouthOpenness
    else {
      return .none
    }

    if learnNeutral {
      neutralLeftEye = blend(neutralLeftEye, left)
      neutralRightEye = blend(neutralRightEye, right)
      neutralMouth = blend(neutralMouth, mouth)
    }

    let leftBaseline = neutralLeftEye ?? left
    let rightBaseline = neutralRightEye ?? right
    let mouthBaseline = neutralMouth ?? mouth
    let leftWink = left < leftBaseline * 0.52 && right > rightBaseline * 0.72
    let rightWink = right < rightBaseline * 0.52 && left > leftBaseline * 0.72
    let winkActive = leftWink || rightWink
    let mouthActive = mouth > max(0.12, mouthBaseline * 1.75)

    defer {
      winkWasActive = winkActive
      mouthWasActive = mouthActive
    }
    if winkActive && !winkWasActive { return .wink }
    if mouthActive && !mouthWasActive { return .mouthOpen }
    return .none
  }

  mutating func reset() {
    neutralLeftEye = nil
    neutralRightEye = nil
    neutralMouth = nil
    winkWasActive = false
    mouthWasActive = false
  }

  private func blend(_ old: Double?, _ new: Double) -> Double {
    guard let old else { return new }
    return old * 0.96 + new * 0.04
  }
}
