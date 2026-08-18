import Foundation

struct FocusPolicy {
  var stabilityInterval: TimeInterval = 0.09
  var mouseQuietInterval: TimeInterval = 0.28
  var switchCooldown: TimeInterval = 0.24

  private(set) var candidateIdentity: String?
  private(set) var candidateSince: TimeInterval?
  private(set) var lastSwitchAt: TimeInterval = -.infinity

  mutating func shouldTransfer(
    to targetIdentity: String?,
    currentIdentity: String?,
    now: TimeInterval,
    lastPhysicalMouseActivity: TimeInterval
  ) -> Bool {
    guard let targetIdentity, targetIdentity != currentIdentity else {
      candidateIdentity = nil
      candidateSince = nil
      return false
    }

    if candidateIdentity != targetIdentity {
      candidateIdentity = targetIdentity
      candidateSince = now
      return false
    }

    guard let candidateSince,
      now - candidateSince >= stabilityInterval,
      now - lastPhysicalMouseActivity >= mouseQuietInterval,
      now - lastSwitchAt >= switchCooldown
    else {
      return false
    }

    lastSwitchAt = now
    self.candidateIdentity = nil
    self.candidateSince = nil
    return true
  }

  mutating func resetCandidate() {
    candidateIdentity = nil
    candidateSince = nil
  }
}
