import CoreGraphics
import XCTest

@testable import Telepathy

final class ShortcutMatcherTests: XCTestCase {
  func testRightShiftConfirmsOnModifierPress() {
    XCTAssertTrue(
      ShortcutMatcher.shouldConfirm(
        type: .flagsChanged,
        keyCode: 60,
        flags: .maskShift,
        isRepeat: false,
        shortcut: .defaultValue,
        modifierWasDown: false
      )
    )
  }

  func testRightShiftDoesNotConfirmOnReleaseOrRepeat() {
    XCTAssertFalse(
      ShortcutMatcher.shouldConfirm(
        type: .flagsChanged,
        keyCode: 60,
        flags: [],
        isRepeat: false,
        shortcut: .defaultValue,
        modifierWasDown: true
      )
    )
    XCTAssertFalse(
      ShortcutMatcher.shouldConfirm(
        type: .flagsChanged,
        keyCode: 60,
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
