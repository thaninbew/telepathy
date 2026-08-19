import CoreGraphics
import Foundation

enum ConfirmationSignal: Equatable {
  case none
  case keyboard
  case mouse
}

struct DisplaySwitchDecision: Equatable {
  enum Phase: Equatable {
    case idle
    case settling(progress: Double)
    case armed
    case holding(progress: Double)
    case commit
  }

  let targetDisplayID: CGDirectDisplayID?
  let phase: Phase
}

struct DisplaySwitchPolicy {
  var stabilityInterval: TimeInterval = 0.09
  var holdInterval: TimeInterval = 0.65
  var mouseQuietInterval: TimeInterval = 0.28
  var switchCooldown: TimeInterval = 0.24

  private(set) var candidateDisplayID: CGDirectDisplayID?
  private(set) var candidateSince: TimeInterval?
  private(set) var lastSwitchAt: TimeInterval = -.infinity

  mutating func evaluate(
    targetDisplayID: CGDirectDisplayID?,
    currentDisplayID: CGDirectDisplayID?,
    mode: ActivationMode,
    now: TimeInterval,
    lastPhysicalMouseActivity: TimeInterval,
    signal: ConfirmationSignal = .none
  ) -> DisplaySwitchDecision {
    guard let targetDisplayID, targetDisplayID != currentDisplayID else {
      resetCandidate()
      return DisplaySwitchDecision(targetDisplayID: nil, phase: .idle)
    }

    if candidateDisplayID != targetDisplayID {
      candidateDisplayID = targetDisplayID
      candidateSince = now
      if stabilityInterval > 0 {
        return DisplaySwitchDecision(targetDisplayID: targetDisplayID, phase: .settling(progress: 0))
      }
    }

    guard let candidateSince else {
      resetCandidate()
      return DisplaySwitchDecision(targetDisplayID: nil, phase: .idle)
    }

    let elapsed = now - candidateSince
    guard elapsed >= stabilityInterval else {
      return DisplaySwitchDecision(
        targetDisplayID: targetDisplayID,
        phase: .settling(progress: min(max(elapsed / stabilityInterval, 0), 1))
      )
    }

    let signalMatches = Self.signal(signal, matches: mode)
    let mouseIsQuiet = now - lastPhysicalMouseActivity >= mouseQuietInterval
    let cooldownExpired = now - lastSwitchAt >= switchCooldown
    let authorityAllowsCommit = (mouseIsQuiet || signalMatches && mode == .mouse) && cooldownExpired

    let wantsCommit: Bool
    let waitingPhase: DisplaySwitchDecision.Phase
    switch mode {
    case .automatic:
      wantsCommit = true
      waitingPhase = .armed
    case .hold:
      let progress = min(max(elapsed / holdInterval, 0), 1)
      wantsCommit = progress >= 1
      waitingPhase = .holding(progress: progress)
    case .keyboard, .mouse:
      wantsCommit = signalMatches
      waitingPhase = .armed
    }

    guard wantsCommit, authorityAllowsCommit else {
      return DisplaySwitchDecision(targetDisplayID: targetDisplayID, phase: waitingPhase)
    }

    lastSwitchAt = now
    resetCandidate()
    return DisplaySwitchDecision(targetDisplayID: targetDisplayID, phase: .commit)
  }

  mutating func resetCandidate() {
    candidateDisplayID = nil
    candidateSince = nil
  }

  private static func signal(_ signal: ConfirmationSignal, matches mode: ActivationMode) -> Bool {
    switch (signal, mode) {
    case (.keyboard, .keyboard), (.mouse, .mouse):
      true
    default:
      false
    }
  }
}
