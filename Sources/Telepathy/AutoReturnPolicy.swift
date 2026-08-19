import CoreGraphics
import Foundation

struct AutoReturnPlan: Equatable {
  let originDisplayID: CGDirectDisplayID
  let temporaryDisplayID: CGDirectDisplayID
}

struct AutoReturnPolicy {
  private(set) var plan: AutoReturnPlan?
  private(set) var suppressedDisplayID: CGDirectDisplayID?

  mutating func switched(
    from originDisplayID: CGDirectDisplayID?,
    to targetDisplayID: CGDirectDisplayID,
    enabled: Bool
  ) -> AutoReturnPlan? {
    if plan?.originDisplayID == targetDisplayID {
      cancel()
      return nil
    }

    guard enabled, let originDisplayID, originDisplayID != targetDisplayID else {
      plan = nil
      return nil
    }

    let next = AutoReturnPlan(
      originDisplayID: originDisplayID,
      temporaryDisplayID: targetDisplayID
    )
    plan = next
    suppressedDisplayID = nil
    return next
  }

  mutating func fire(_ expectedPlan: AutoReturnPlan) -> CGDirectDisplayID? {
    guard plan == expectedPlan else { return nil }
    plan = nil
    suppressedDisplayID = expectedPlan.temporaryDisplayID
    return expectedPlan.originDisplayID
  }

  mutating func shouldSuppress(_ predictedDisplayID: CGDirectDisplayID) -> Bool {
    guard let suppressedDisplayID else { return false }
    if predictedDisplayID == suppressedDisplayID { return true }
    self.suppressedDisplayID = nil
    return false
  }

  @discardableResult
  mutating func pointerActivity(on displayID: CGDirectDisplayID) -> Bool {
    guard plan?.temporaryDisplayID == displayID else { return false }
    cancel()
    return true
  }

  mutating func cancel() {
    plan = nil
    suppressedDisplayID = nil
  }

  mutating func returnFailed() {
    suppressedDisplayID = nil
  }
}
