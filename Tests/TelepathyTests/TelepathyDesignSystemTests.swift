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

  func testStatusItemUsesTheSentinelMarkAsATemplateImage() {
    let image = TelepathyLogoView.statusItemImage()

    XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
    XCTAssertTrue(image.isTemplate)
    XCTAssertEqual(image.accessibilityDescription, "Telepathy")
  }

  func testStatusItemMarkHasVisibleAlphaCoverage() throws {
    let image = TelepathyLogoView.statusItemImage()
    let representation = try XCTUnwrap(image.tiffRepresentation)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: representation))
    var visiblePixels = 0

    for x in 0..<bitmap.pixelsWide {
      for y in 0..<bitmap.pixelsHigh where bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 > 0.1 {
        visiblePixels += 1
      }
    }

    XCTAssertGreaterThan(visiblePixels, 80)
  }
}
