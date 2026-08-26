import Foundation

struct FeedbackPresentationPolicy {
  var revealInterval: TimeInterval = 0.18
  var candidateVisibleInterval: TimeInterval = 0.42

  func phase(
    for decision: DisplaySwitchDecision,
    candidateSince: TimeInterval?,
    stabilityInterval: TimeInterval,
    now: TimeInterval
  ) -> DisplayFeedbackPhase? {
    guard let candidateSince else { return nil }
    let elapsed = max(now - candidateSince, 0)

    switch decision.phase {
    case .idle, .settling, .commit:
      return nil
    case .armed:
      let visibleSince = max(revealInterval, stabilityInterval)
      return elapsed >= visibleSince && elapsed <= visibleSince + candidateVisibleInterval
        ? .candidate
        : nil
    case .holding(let progress):
      return elapsed >= revealInterval ? .holding(progress: progress) : nil
    }
  }
}
