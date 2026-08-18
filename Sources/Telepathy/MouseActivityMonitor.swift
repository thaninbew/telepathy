import AppKit
import CoreGraphics
import Foundation

final class MouseActivityMonitor {
  var onClick: ((CGPoint, TimeInterval) -> Void)?
  var onEmergencyToggle: (() -> Void)?

  private(set) var lastPhysicalMouseActivity: TimeInterval = -.infinity
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var ignoreMotionUntil: TimeInterval = -.infinity

  var isRunning: Bool { eventTap != nil }

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

    if type == .keyDown {
      let flags = event.flags
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      if keyCode == 53, flags.contains(.maskCommand), flags.contains(.maskAlternate) {
        onEmergencyToggle?()
      }
      return
    }

    if type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged
      || type == .otherMouseDragged
    {
      guard now >= ignoreMotionUntil else { return }
      lastPhysicalMouseActivity = now
      return
    }

    if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
      lastPhysicalMouseActivity = now
      onClick?(event.location, now)
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
