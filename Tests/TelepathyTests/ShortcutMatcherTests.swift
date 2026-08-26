import CoreGraphics
import XCTest

@testable import Telepathy

final class ShortcutMatcherTests: XCTestCase {
  func testDefaultShortcutIsLeftShift() {
    XCTAssertEqual(ShortcutBinding.defaultValue.keyCode, 56)
    XCTAssertEqual(ShortcutBinding.defaultValue.displayName, "Left Shift")
  }

  func testLeftShiftConfirmsOnModifierPress() {
    XCTAssertTrue(
      ShortcutMatcher.shouldConfirm(
        type: .flagsChanged,
        keyCode: 56,
        flags: .maskShift,
        isRepeat: false,
        shortcut: .defaultValue,
        modifierWasDown: false
      )
    )
  }

  func testLeftShiftDoesNotConfirmOnReleaseOrRepeat() {
    XCTAssertFalse(
      ShortcutMatcher.shouldConfirm(
        type: .flagsChanged,
        keyCode: 56,
        flags: [],
        isRepeat: false,
        shortcut: .defaultValue,
        modifierWasDown: true
      )
    )
    XCTAssertFalse(
      ShortcutMatcher.shouldConfirm(
        type: .flagsChanged,
        keyCode: 56,
        flags: .maskShift,
        isRepeat: false,
        shortcut: .defaultValue,
        modifierWasDown: true
      )
    )
  }

  func testOrdinaryRecordedKeyConfirmsOnlyMatchingNonRepeatKeyDown() {
    let space = ShortcutBinding(keyCode: 49, displayName: "Space")
    XCTAssertTrue(
      ShortcutMatcher.shouldConfirm(
        type: .keyDown,
        keyCode: 49,
        flags: [],
        isRepeat: false,
        shortcut: space,
        modifierWasDown: false
      )
    )
    XCTAssertFalse(
      ShortcutMatcher.shouldConfirm(
        type: .keyDown,
        keyCode: 49,
        flags: [],
        isRepeat: true,
        shortcut: space,
        modifierWasDown: false
      )
    )
  }
}
