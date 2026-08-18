import AppKit

enum OverlayStyle {
  // Instrument / monochrome: neutral telemetry with one warm signal color.
  static let background = NSColor(
    calibratedRed: 22 / 255, green: 20 / 255, blue: 19 / 255, alpha: 1)
  static let surface = NSColor(
    calibratedRed: 31 / 255, green: 28 / 255, blue: 25 / 255, alpha: 1)
  static let surfaceRaised = NSColor(
    calibratedRed: 38 / 255, green: 35 / 255, blue: 32 / 255, alpha: 1)
  static let border = NSColor(
    calibratedRed: 69 / 255, green: 63 / 255, blue: 55 / 255, alpha: 1)
  static let accent = NSColor(calibratedRed: 224 / 255, green: 164 / 255, blue: 88 / 255, alpha: 1)
  static let accentMuted = accent.withAlphaComponent(0.58)
  static let accentFaint = accent.withAlphaComponent(0.18)
  static let ink = NSColor(calibratedRed: 22 / 255, green: 20 / 255, blue: 19 / 255, alpha: 0.88)
  static let text = NSColor(
    calibratedRed: 243 / 255, green: 238 / 255, blue: 230 / 255, alpha: 0.94)
  static let telemetry = NSColor(
    calibratedRed: 183 / 255, green: 173 / 255, blue: 158 / 255, alpha: 0.82)
  static let idle = NSColor(
    calibratedRed: 154 / 255, green: 145 / 255, blue: 132 / 255, alpha: 1)
  static let rawSignal = NSColor.white.withAlphaComponent(0.42)

  static let markerRadius: CGFloat = 5
  static let markerHaloRadius: CGFloat = 11
  static let windowCornerRadius: CGFloat = 10
  static let panelCornerRadius: CGFloat = 16
  static let space1: CGFloat = 4
  static let space2: CGFloat = 8
  static let space3: CGFloat = 12
  static let space4: CGFloat = 16
  static let space6: CGFloat = 24
}
