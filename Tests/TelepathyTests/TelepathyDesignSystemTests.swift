import XCTest

@testable import Telepathy

@MainActor
final class TelepathyDesignSystemTests: XCTestCase {
  func testTextContrastPassesOnEverySurfaceInBothAppearances() {
    for mode in [TelepathySemantic.Mode.light, .dark] {
      let palette = TelepathySemantic.palette(for: mode)
      for surface in [palette.background, palette.sidebar, palette.surface, palette.raised] {
        XCTAssertGreaterThanOrEqual(TelepathyContrast.ratio(palette.text, surface), 4.5)
        XCTAssertGreaterThanOrEqual(
          TelepathyContrast.ratio(palette.secondaryText, surface),
          4.5
        )
      }
    }
  }

  func testCustomAccentPassesUIContrastOnBothAppearances() {
    let accent = AccentTheme.defaultValue.customColor
    for mode in [TelepathySemantic.Mode.light, .dark] {
      let background = AccentColor(color: TelepathySemantic.palette(for: mode).surface)
      let adjusted = accent.adjustedForContrast(against: background, minimumRatio: 3)
      XCTAssertGreaterThanOrEqual(adjusted.contrastRatio(against: background), 3)
    }
  }

  func testSemanticColorsResolveAgainstTheRequestedAppearance() throws {
    let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
    let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

    let resolvedLight = TelepathySemantic.resolved(
      TelepathySemantic.surface,
      for: lightAppearance
    )
    let resolvedDark = TelepathySemantic.resolved(
      TelepathySemantic.surface,
      for: darkAppearance
    )

    XCTAssertEqual(
      AccentColor(color: resolvedLight),
      AccentColor(color: TelepathySemantic.palette(for: .light).surface)
    )
    XCTAssertEqual(
      AccentColor(color: resolvedDark),
      AccentColor(color: TelepathySemantic.palette(for: .dark).surface)
    )
    XCTAssertEqual(TelepathySemantic.mode(for: lightAppearance), .light)
    XCTAssertEqual(TelepathySemantic.mode(for: darkAppearance), .dark)
  }

  func testSentinelAccentRemainsLegibleInBothAppearances() {
    let theme = AccentTheme.defaultValue

    for mode in [TelepathySemantic.Mode.light, .dark] {
      let accent = AccentColor(color: TelepathySemantic.panelAccent(for: theme, mode: mode))
      let palette = TelepathySemantic.palette(for: mode)
      let raised = AccentColor(color: palette.raised)
      let surface = AccentColor(color: palette.surface)

      XCTAssertGreaterThanOrEqual(accent.contrastRatio(against: raised), 3)
      XCTAssertGreaterThanOrEqual(accent.contrastRatio(against: surface), 3)
    }
  }

  func testSentinelTileRefreshesWhenAppearanceChanges() throws {
    let logo = TelepathyLogoView(frame: NSRect(x: 0, y: 0, width: 38, height: 38))
    let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
    let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

    logo.appearance = lightAppearance
    logo.viewDidChangeEffectiveAppearance()
    let lightBackground = try XCTUnwrap(logo.layer?.backgroundColor)

    logo.appearance = darkAppearance
    logo.viewDidChangeEffectiveAppearance()
    let darkBackground = try XCTUnwrap(logo.layer?.backgroundColor)

    XCTAssertEqual(
      AccentColor(color: try XCTUnwrap(NSColor(cgColor: lightBackground))),
      AccentColor(color: TelepathySemantic.palette(for: .light).raised)
    )
    XCTAssertEqual(
      AccentColor(color: try XCTUnwrap(NSColor(cgColor: darkBackground))),
      AccentColor(color: TelepathySemantic.palette(for: .dark).raised)
    )
  }

  func testStatusItemUsesTheSentinelMarkAsATemplateImage() {
    let image = TelepathyLogoView.statusItemImage()

    XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
    XCTAssertTrue(image.isTemplate)
    XCTAssertEqual(image.accessibilityDescription, "Telepathy")
  }
}
