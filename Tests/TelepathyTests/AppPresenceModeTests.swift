import AppKit
import XCTest

@testable import Telepathy

final class AppPresenceModeTests: XCTestCase {
  func testModesExposeEveryNativeVisibilityCombination() {
    XCTAssertEqual(AppPresenceMode.allCases, [.standard, .menuBarOnly, .dockOnly, .hidden])
    XCTAssertEqual(AppPresenceMode.standard.activationPolicy, .regular)
    XCTAssertTrue(AppPresenceMode.standard.showsMenuBarItem)
    XCTAssertEqual(AppPresenceMode.menuBarOnly.activationPolicy, .accessory)
    XCTAssertTrue(AppPresenceMode.menuBarOnly.showsMenuBarItem)
    XCTAssertEqual(AppPresenceMode.dockOnly.activationPolicy, .regular)
    XCTAssertFalse(AppPresenceMode.dockOnly.showsMenuBarItem)
    XCTAssertEqual(AppPresenceMode.hidden.activationPolicy, .accessory)
    XCTAssertFalse(AppPresenceMode.hidden.showsMenuBarItem)
  }

  func testStoredModeDefaultsToStandardAndRejectsUnknownValues() throws {
    let suiteName = "AppPresenceModeTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    XCTAssertEqual(AppPresenceMode.stored(in: defaults), .standard)
    defaults.set("future-mode", forKey: AppPresenceMode.defaultsKey)
    XCTAssertEqual(AppPresenceMode.stored(in: defaults), .standard)
  }

  func testStoredModeRestoresEverySupportedSelection() throws {
    let suiteName = "AppPresenceModeTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    for mode in AppPresenceMode.allCases {
      defaults.set(mode.rawValue, forKey: AppPresenceMode.defaultsKey)
      XCTAssertEqual(AppPresenceMode.stored(in: defaults), mode)
    }
  }

  func testEveryModeExplainsItsVisibleRecoverySurface() {
    for mode in AppPresenceMode.allCases {
      XCTAssertFalse(mode.title.isEmpty)
      XCTAssertFalse(mode.detail.isEmpty)
    }
    XCTAssertTrue(AppPresenceMode.hidden.detail.contains("Spotlight"))
  }
}
