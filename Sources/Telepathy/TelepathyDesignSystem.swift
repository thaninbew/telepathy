import AppKit

// Frontend-design v2 contract for the control panel.
// Direction: instrument / monochrome, native macOS.
// Vocabulary: one grouped surface, native AppKit inputs, native primary and quiet actions.
// Standard AppKit controls own hover, focus, active, disabled, and reduced-motion behavior.
@MainActor
enum TelepathyPrimitive {
  enum Space {
    static let x1: CGFloat = 4
    static let x2: CGFloat = 8
    static let x3: CGFloat = 12
    static let x4: CGFloat = 16
    static let x6: CGFloat = 24
    static let x8: CGFloat = 32
  }

  enum Radius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
  }

  @MainActor
  enum Typography {
    static let pageTitle = NSFont.systemFont(ofSize: 24, weight: .semibold)
    static let pageDetail = NSFont.systemFont(ofSize: 13, weight: .regular)
    static let rowTitle = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let rowDetail = NSFont.systemFont(ofSize: 11, weight: .regular)
    static let status = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let sidebarTitle = NSFont.systemFont(ofSize: 14, weight: .semibold)
    static let sidebarDetail = NSFont.systemFont(ofSize: 11, weight: .regular)
  }

  @MainActor
  enum Palette {
    static let lightBackground = NSColor(srgbRed: 0.957, green: 0.957, blue: 0.969, alpha: 1)
    static let lightSidebar = NSColor(srgbRed: 0.914, green: 0.914, blue: 0.929, alpha: 1)
    static let lightSurface = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    static let lightRaised = NSColor(srgbRed: 0.949, green: 0.949, blue: 0.961, alpha: 1)
    static let lightText = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1)
    static let lightSecondary = NSColor(srgbRed: 0.345, green: 0.345, blue: 0.369, alpha: 1)
    static let lightBorder = NSColor(srgbRed: 0.800, green: 0.800, blue: 0.824, alpha: 1)

    static let darkBackground = NSColor(srgbRed: 0.118, green: 0.118, blue: 0.129, alpha: 1)
    static let darkSidebar = NSColor(srgbRed: 0.153, green: 0.153, blue: 0.165, alpha: 1)
    static let darkSurface = NSColor(srgbRed: 0.184, green: 0.184, blue: 0.196, alpha: 1)
    static let darkRaised = NSColor(srgbRed: 0.224, green: 0.224, blue: 0.239, alpha: 1)
    static let darkText = NSColor(srgbRed: 0.949, green: 0.949, blue: 0.969, alpha: 1)
    static let darkSecondary = NSColor(srgbRed: 0.702, green: 0.702, blue: 0.722, alpha: 1)
    static let darkBorder = NSColor(srgbRed: 0.286, green: 0.286, blue: 0.306, alpha: 1)
  }
}

@MainActor
struct TelepathySemanticPalette {
  let background: NSColor
  let sidebar: NSColor
  let surface: NSColor
  let raised: NSColor
  let text: NSColor
  let secondaryText: NSColor
  let border: NSColor
}

@MainActor
enum TelepathySemantic {
  enum Mode {
    case light
    case dark
  }

  static let background = dynamic(\.background)
  static let sidebar = dynamic(\.sidebar)
  static let surface = dynamic(\.surface)
  static let raised = dynamic(\.raised)
  static let text = dynamic(\.text)
  static let secondaryText = dynamic(\.secondaryText)
  static let border = dynamic(\.border)

  static func palette(for mode: Mode) -> TelepathySemanticPalette {
    switch mode {
    case .light:
      TelepathySemanticPalette(
        background: TelepathyPrimitive.Palette.lightBackground,
        sidebar: TelepathyPrimitive.Palette.lightSidebar,
        surface: TelepathyPrimitive.Palette.lightSurface,
        raised: TelepathyPrimitive.Palette.lightRaised,
        text: TelepathyPrimitive.Palette.lightText,
        secondaryText: TelepathyPrimitive.Palette.lightSecondary,
        border: TelepathyPrimitive.Palette.lightBorder
      )
    case .dark:
      TelepathySemanticPalette(
        background: TelepathyPrimitive.Palette.darkBackground,
        sidebar: TelepathyPrimitive.Palette.darkSidebar,
        surface: TelepathyPrimitive.Palette.darkSurface,
        raised: TelepathyPrimitive.Palette.darkRaised,
        text: TelepathyPrimitive.Palette.darkText,
        secondaryText: TelepathyPrimitive.Palette.darkSecondary,
        border: TelepathyPrimitive.Palette.darkBorder
      )
    }
  }

  static func panelAccent(for theme: AccentTheme) -> NSColor {
    guard theme.source == .custom else { return .controlAccentColor }
    let preferred = theme.customColor
    let light = preferred.adjustedForContrast(
      against: AccentColor(color: palette(for: .light).surface), minimumRatio: 3
    ).nsColor
    let dark = preferred.adjustedForContrast(
      against: AccentColor(color: palette(for: .dark).surface), minimumRatio: 3
    ).nsColor
    return dynamic(light: light, dark: dark)
  }

  private static func dynamic(_ keyPath: KeyPath<TelepathySemanticPalette, NSColor>) -> NSColor {
    dynamic(
      light: palette(for: .light)[keyPath: keyPath],
      dark: palette(for: .dark)[keyPath: keyPath]
    )
  }

  private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    }
  }
}

@MainActor
enum TelepathyComponent {
  static let windowSize = NSSize(width: 760, height: 590)
  static let minimumWindowSize = NSSize(width: 680, height: 520)
  static let sidebarWidth: CGFloat = 184
  static let sidebarInset = TelepathyPrimitive.Space.x3
  static let contentInset = TelepathyPrimitive.Space.x8
  static let sectionGap = TelepathyPrimitive.Space.x6
  static let rowInset = TelepathyPrimitive.Space.x4
  static let rowGap = TelepathyPrimitive.Space.x2
  static let rowMinimumHeight: CGFloat = 54
  static let groupRadius = TelepathyPrimitive.Radius.medium
  static let iconRadius = TelepathyPrimitive.Radius.small
  static let dividerWidth: CGFloat = 1
  static let statusDotSize: CGFloat = 7
  static let logoSize: CGFloat = 38
  static let logoMarkSize = NSSize(width: 28, height: 28)
  static let sourceListRowHeight: CGFloat = 32

  static let pageTitleFont = TelepathyPrimitive.Typography.pageTitle
  static let pageDetailFont = TelepathyPrimitive.Typography.pageDetail
  static let rowTitleFont = TelepathyPrimitive.Typography.rowTitle
  static let rowDetailFont = TelepathyPrimitive.Typography.rowDetail
  static let statusFont = TelepathyPrimitive.Typography.status
  static let sidebarTitleFont = TelepathyPrimitive.Typography.sidebarTitle
  static let sidebarDetailFont = TelepathyPrimitive.Typography.sidebarDetail
}

@MainActor
enum TelepathyContrast {
  static func ratio(_ first: NSColor, _ second: NSColor) -> Double {
    let firstLuminance = luminance(first)
    let secondLuminance = luminance(second)
    return (max(firstLuminance, secondLuminance) + 0.05)
      / (min(firstLuminance, secondLuminance) + 0.05)
  }

  private static func luminance(_ color: NSColor) -> Double {
    let converted = color.usingColorSpace(.sRGB) ?? color
    return 0.2126 * linearized(Double(converted.redComponent))
      + 0.7152 * linearized(Double(converted.greenComponent))
      + 0.0722 * linearized(Double(converted.blueComponent))
  }

  private static func linearized(_ value: Double) -> Double {
    value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
  }
}
