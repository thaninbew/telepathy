import AppKit
import CoreGraphics
import Foundation

final class MouseActivityMonitor {
  var onClick: ((CGPoint, TimeInterval) -> Void)?
  var onEmergencyToggle: (() -> Void)?
  var onPointerActivity: ((CGPoint, TimeInterval) -> Void)?
  var onConfirmation: ((ConfirmationSignal, TimeInterval) -> Void)?
  var shortcut = ShortcutBinding.defaultValue {
    didSet { pressedModifierKeyCodes.removeAll() }
  }

  private(set) var lastPhysicalMouseActivity: TimeInterval = -.infinity
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var ignoreMotionUntil: TimeInterval = -.infinity
  private var pressedModifierKeyCodes: Set<Int64> = []

  var isRunning: Bool { eventTap != nil }
  var isShortcutPressed: Bool {
    ShortcutMatcher.modifierFlag(for: shortcut.keyCode) != nil
      && pressedModifierKeyCodes.contains(shortcut.keyCode)
  }

  func start() -> Bool {
    guard eventTap == nil else { return true }

    let eventTypes: [CGEventType] = [
      .mouseMoved,
      .leftMouseDragged,
      .rightMouseDragged,
      .otherMouseDragged,
      .leftMouseDown,
      .rightMouseDown,
      .otherMouseDown,
      .keyDown,
      .flagsChanged,
    ]
    let mask = eventTypes.reduce(CGEventMask(0)) {
      $0 | (CGEventMask(1) << CGEventMask($1.rawValue))
    }

    let pointer = Unmanaged.passUnretained(self).toOpaque()
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: mask,
        callback: telepathyEventTapCallback,
        userInfo: pointer
      )
    else {
      return false
    }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    eventTap = tap
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
  }

  func stop() {
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    eventTap = nil
    runLoopSource = nil
  }

  func prepareForCursorWarp(now: TimeInterval) {
    ignoreMotionUntil = now + 0.12
  }

  fileprivate func handle(type: CGEventType, event: CGEvent) {
    let now = ProcessInfo.processInfo.systemUptime

    if type == .keyDown || type == .flagsChanged {
      let flags = event.flags
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      if type == .keyDown, keyCode == 53, flags.contains(.maskCommand),
        flags.contains(.maskAlternate)
      {
        onEmergencyToggle?()
      } else if ShortcutMatcher.shouldConfirm(
        type: type,
        keyCode: keyCode,
        flags: flags,
        isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
        shortcut: shortcut,
        modifierWasDown: pressedModifierKeyCodes.contains(keyCode)
      ) {
        if type == .flagsChanged {
          pressedModifierKeyCodes.insert(keyCode)
        }
        onConfirmation?(.keyboard, now)
      } else if type == .flagsChanged, pressedModifierKeyCodes.contains(keyCode) {
        // A flagsChanged event for a tracked modifier is its release. Remove it
        // even if the matching left/right modifier keeps the aggregate flag set.
        pressedModifierKeyCodes.remove(keyCode)
      }
      return
    }

    if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged
      || type == .otherMouseDragged
    {
      guard now >= ignoreMotionUntil else { return }
      lastPhysicalMouseActivity = now
      onPointerActivity?(event.location, now)
      return
    }

    if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
      lastPhysicalMouseActivity = now
      onPointerActivity?(event.location, now)
      var isConfirmationClick = false
      if type == .otherMouseDown,
        event.getIntegerValueField(.mouseEventButtonNumber) == 2
      {
        isConfirmationClick = true
        onConfirmation?(.mouse, now)
      }
      if !isConfirmationClick { onClick?(event.location, now) }
    }
  }
}

enum ShortcutMatcher {
  static func shouldConfirm(
    type: CGEventType,
    keyCode: Int64,
    flags: CGEventFlags,
    isRepeat: Bool,
    shortcut: ShortcutBinding,
    modifierWasDown: Bool
  ) -> Bool {
    guard keyCode == shortcut.keyCode else { return false }
    if type == .keyDown { return !isRepeat }
    guard type == .flagsChanged, !modifierWasDown,
      let flag = modifierFlag(for: keyCode)
    else { return false }
    return flags.contains(flag)
  }

  static func modifierFlag(for keyCode: Int64) -> CGEventFlags? {
    switch keyCode {
    case 56, 60: .maskShift
    case 59, 62: .maskControl
    case 58, 61: .maskAlternate
    case 54, 55: .maskCommand
    case 57: .maskAlphaShift
    default: nil
    }
  }
}

private func telepathyEventTapCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  let monitor = Unmanaged<MouseActivityMonitor>.fromOpaque(userInfo).takeUnretainedValue()
  monitor.handle(type: type, event: event)
  return Unmanaged.passUnretained(event)
}
