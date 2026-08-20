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
}
