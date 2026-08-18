import CoreGraphics
import XCTest

@testable import Telepathy

final class DesktopGeometryTests: XCTestCase {
  func testFingerprintIsIndependentOfEnumerationOrder() {
    let main = display(serial: 1, isMain: true, bounds: CGRect(x: 0, y: 0, width: 100, height: 80))
    let side = display(
      serial: 2, isMain: false, bounds: CGRect(x: 100, y: 20, width: 60, height: 40))

    XCTAssertEqual(
      DesktopGeometry.fingerprint(for: [main, side]),
      DesktopGeometry.fingerprint(for: [side, main])
    )
  }

  func testFingerprintChangesWhenLayoutChanges() {
    let original = display(
      serial: 1, isMain: true, bounds: CGRect(x: 0, y: 0, width: 100, height: 80))
    let moved = display(
      serial: 1, isMain: true, bounds: CGRect(x: 100, y: 0, width: 100, height: 80))

    XCTAssertNotEqual(
      DesktopGeometry.fingerprint(for: [original]),
      DesktopGeometry.fingerprint(for: [moved])
    )
  }

  func testSpanningWindowBelongsToDisplayWithLargestIntersection() {
    let displays = [
      ActiveDisplay(
        id: 1,
        bounds: CGRect(x: 0, y: 0, width: 1_000, height: 800),
        visibleBounds: CGRect(x: 0, y: 0, width: 1_000, height: 760)
      ),
      ActiveDisplay(
        id: 2,
        bounds: CGRect(x: 1_000, y: 0, width: 1_000, height: 800),
        visibleBounds: CGRect(x: 1_000, y: 0, width: 1_000, height: 760)
      ),
    ]
    let window = CGRect(x: 850, y: 100, width: 700, height: 500)

    XCTAssertEqual(DesktopGeometry.display(owning: window, in: displays)?.id, 2)
  }

  private func display(
    serial: UInt32,
    isMain: Bool,
    bounds: CGRect
  ) -> DisplayGeometry {
    DisplayGeometry(
      vendor: 10,
      model: 20,
      serial: serial,
      isBuiltIn: serial == 1,
      isMain: isMain,
      bounds: bounds,
      pixelWidth: Int(bounds.width * 2),
      pixelHeight: Int(bounds.height * 2),
      rotation: 0
    )
  }
}
