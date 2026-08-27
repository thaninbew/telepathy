import AppKit
import XCTest

@testable import Telepathy

@MainActor
final class TelepathyStatusMenuTests: XCTestCase {
  func testStatusMenuKeepsOnlyQuickControlsAtTheTopLevel() {
    let controller = TelepathyController()
    let menu = NSMenu(title: "Telepathy")

    controller.rebuildStatusMenu(menu)

    let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
    XCTAssertEqual(titles.first, "Open Telepathy…")
    XCTAssertTrue(titles.contains("Activation"))
    XCTAssertTrue(titles.contains("Feedback"))
    XCTAssertTrue(titles.contains("Move Pointer with Focus"))
    XCTAssertTrue(titles.contains("Calibration"))
    XCTAssertEqual(titles.last, "Quit Telepathy")
    XCTAssertFalse(titles.contains("Show screen shine"))
    XCTAssertFalse(titles.contains("Show experimental gaze indicator"))
    XCTAssertFalse(titles.contains("Full Calibration…"))
    XCTAssertFalse(titles.contains(where: { $0.hasPrefix("Emergency pause:") }))
  }

  func testStatusMenuGroupsSecondaryControlsAndShowsEmergencyShortcut() throws {
    let controller = TelepathyController()
    let menu = NSMenu(title: "Telepathy")

    controller.rebuildStatusMenu(menu)

    let toggleItem = try XCTUnwrap(
      menu.items.first(where: { $0.title == "Pause Telepathy" || $0.title == "Resume Telepathy" })
    )
    XCTAssertEqual(toggleItem.keyEquivalent, "\u{1b}")
    XCTAssertEqual(toggleItem.keyEquivalentModifierMask, [.command, .option])

    let activation = try XCTUnwrap(menu.item(withTitle: "Activation")?.submenu)
    XCTAssertTrue(
      activation.items.contains(where: { $0.title == "Allow Activation While Moving Pointer" }))
    XCTAssertTrue(activation.items.contains(where: { $0.title == "Change Keyboard Shortcut…" }))

    let feedback = try XCTUnwrap(menu.item(withTitle: "Feedback")?.submenu)
    XCTAssertEqual(
      feedback.items.filter { !$0.isSeparatorItem }.map(\.title),
      ["Screen Shine", "Gaze Indicator (Experimental)"]
    )

    let calibration = try XCTUnwrap(menu.item(withTitle: "Calibration")?.submenu)
    XCTAssertEqual(
      calibration.items.filter { !$0.isSeparatorItem }.map(\.title),
      ["Quick Recenter…", "Full Calibration…", "Reset Calibration…"]
    )
  }
}
