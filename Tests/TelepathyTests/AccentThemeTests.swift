import AppKit
import XCTest

@testable import Telepathy

final class AccentThemeTests: XCTestCase {
  func testDefaultGoldMeetsControlContrastFloor() {
    let resolved = AccentTheme.defaultValue.resolved(
      systemAccent: .systemBlue,
      against: OverlayStyle.surface
    )
    XCTAssertGreaterThanOrEqual(
      resolved.contrastRatio(against: AccentColor(color: OverlayStyle.surface)),
      3
    )
  }

  func testDarkCustomColorIsLiftedToMeetContrastFloor() {
    let surface = AccentColor(color: OverlayStyle.surface)
    let dark = AccentColor(red: 0.01, green: 0.01, blue: 0.01)
    let resolved = AccentTheme(source: .custom, customColor: dark).resolved(
      systemAccent: .systemBlue,
      against: OverlayStyle.surface
    )

    XCTAssertGreaterThanOrEqual(resolved.contrastRatio(against: surface), 3)
    XCTAssertNotEqual(resolved, dark)
  }

  func testReadableCustomColorIsNotChanged() {
    let bright = AccentColor(red: 0.9, green: 0.4, blue: 0.8)
    let resolved = AccentTheme(source: .custom, customColor: bright).resolved(
      systemAccent: .systemBlue,
      against: OverlayStyle.surface
    )
    XCTAssertEqual(resolved, bright)
  }

  func testThemeRoundTripsThroughPersistenceFormat() throws {
    let theme = AccentTheme(
      source: .custom,
      customColor: AccentColor(red: 0.2, green: 0.7, blue: 0.4)
    )
    let decoded = try JSONDecoder().decode(
      AccentTheme.self,
      from: JSONEncoder().encode(theme)
    )
    XCTAssertEqual(decoded, theme)
  }
}
