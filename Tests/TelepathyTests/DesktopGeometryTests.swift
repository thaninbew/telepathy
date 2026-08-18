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
