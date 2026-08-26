import Foundation

enum ConfirmationTiming {
  static func latchInterval(switchDelay: TimeInterval) -> TimeInterval {
    max(0.5, switchDelay + 0.25)
  }
}
