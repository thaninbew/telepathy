import AppKit
import Foundation

enum AccentThemeSource: String, CaseIterable, Codable {
  case system
  case custom

  var title: String {
    switch self {
    case .system: "macOS"
    case .custom: "Custom"
    }
  }
}

struct AccentColor: Codable, Equatable {
  let red: Double
  let green: Double
  let blue: Double

  static let gold = AccentColor(
    red: 224 / 255,
    green: 164 / 255,
    blue: 88 / 255
  )

  init(red: Double, green: Double, blue: Double) {
    self.red = min(max(red, 0), 1)
    self.green = min(max(green, 0), 1)
    self.blue = min(max(blue, 0), 1)
  }

  init(color: NSColor) {
    let converted = color.usingColorSpace(.sRGB) ?? color
    self.init(
      red: Double(converted.redComponent),
      green: Double(converted.greenComponent),
      blue: Double(converted.blueComponent)
    )
  }

  var nsColor: NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
  }

  func adjustedForContrast(
    against background: AccentColor,
    minimumRatio: Double = 3
  ) -> AccentColor {
    guard contrastRatio(against: background) < minimumRatio else { return self }

    for step in 1...20 {
      let amount = Double(step) / 20
      let lighter = AccentColor(
        red: red + (1 - red) * amount,
        green: green + (1 - green) * amount,
        blue: blue + (1 - blue) * amount
      )
      let darker = AccentColor(
        red: red * (1 - amount),
        green: green * (1 - amount),
        blue: blue * (1 - amount)
      )
      let lighterRatio = lighter.contrastRatio(against: background)
      let darkerRatio = darker.contrastRatio(against: background)
      if lighterRatio >= minimumRatio || darkerRatio >= minimumRatio {
        return lighterRatio >= darkerRatio ? lighter : darker
      }
    }
    let light = AccentColor(red: 1, green: 1, blue: 1)
    let dark = AccentColor(red: 0, green: 0, blue: 0)
    return light.contrastRatio(against: background) >= dark.contrastRatio(against: background)
      ? light : dark
  }

  func contrastRatio(against other: AccentColor) -> Double {
    let brighter = max(relativeLuminance, other.relativeLuminance)
    let darker = min(relativeLuminance, other.relativeLuminance)
    return (brighter + 0.05) / (darker + 0.05)
  }

  private var relativeLuminance: Double {
    0.2126 * Self.linearized(red)
      + 0.7152 * Self.linearized(green)
      + 0.0722 * Self.linearized(blue)
  }

  private static func linearized(_ value: Double) -> Double {
    value <= 0.04045
      ? value / 12.92
      : pow((value + 0.055) / 1.055, 2.4)
  }
}

struct AccentTheme: Codable, Equatable {
  var source: AccentThemeSource
  var customColor: AccentColor

  static let defaultValue = AccentTheme(source: .custom, customColor: .gold)

  func resolved(
    systemAccent: NSColor = .controlAccentColor,
    against background: NSColor = OverlayStyle.surface
  ) -> AccentColor {
    let selected = source == .system ? AccentColor(color: systemAccent) : customColor
    return selected.adjustedForContrast(against: AccentColor(color: background))
  }
}
