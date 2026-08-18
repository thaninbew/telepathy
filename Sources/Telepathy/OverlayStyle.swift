import AppKit

enum OverlayStyle {
  // Instrument / monochrome: neutral telemetry with one warm signal color.
  static let accent = NSColor(calibratedRed: 224 / 255, green: 164 / 255, blue: 88 / 255, alpha: 1)
  static let accentMuted = accent.withAlphaComponent(0.58)
  static let accentFaint = accent.withAlphaComponent(0.18)
  static let ink = NSColor(calibratedRed: 22 / 255, green: 20 / 255, blue: 19 / 255, alpha: 0.88)
  static let text = NSColor(
    calibratedRed: 243 / 255, green: 238 / 255, blue: 230 / 255, alpha: 0.94)
  static let telemetry = NSColor(
    calibratedRed: 183 / 255, green: 173 / 255, blue: 158 / 255, alpha: 0.82)
  static let rawSignal = NSColor.white.withAlphaComponent(0.42)

  static let markerRadius: CGFloat = 5
  static let markerHaloRadius: CGFloat = 11
  static let windowCornerRadius: CGFloat = 10
  static let statusCornerRadius: CGFloat = 10
  static let space1: CGFloat = 4
  static let space2: CGFloat = 8
  static let space3: CGFloat = 12
}
