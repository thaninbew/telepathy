import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct AccessibilityTarget {
  let metadata: TargetWindow
  let element: AXUIElement
}

@MainActor
final class AccessibilityWindowController {
  var isTrusted: Bool { AXIsProcessTrusted() }

  func openTrustSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    else { return }
    NSWorkspace.shared.open(url)
  }

  func focusedWindow() -> AccessibilityTarget? {
    guard let running = NSWorkspace.shared.frontmostApplication else { return nil }
    let application = AXUIElementCreateApplication(running.processIdentifier)
    guard
      let focused: AXUIElement = copyAttribute(application, kAXFocusedWindowAttribute as CFString),
      let metadata = metadata(for: focused)
    else { return nil }
    return AccessibilityTarget(metadata: metadata, element: focused)
  }

  func eligibleTarget(
    from remembered: AccessibilityTarget,
    on display: ActiveDisplay,
    excludingProcessIdentifier excludedPID: pid_t
  ) -> AccessibilityTarget? {
    guard remembered.metadata.processIdentifier != excludedPID,
      let running = NSRunningApplication(
        processIdentifier: remembered.metadata.processIdentifier),
      !running.isTerminated,
      !running.isHidden,
      let refreshed = metadata(for: remembered.element),
      !isMinimized(remembered.element),
      DesktopGeometry.display(owning: refreshed.frame)?.id == display.id,
      isOnCurrentSpace(refreshed)
    else { return nil }
    return AccessibilityTarget(metadata: refreshed, element: remembered.element)
  }

  func frontmostEligibleTarget(
    on display: ActiveDisplay,
    excludingProcessIdentifier excludedPID: pid_t
  ) -> AccessibilityTarget? {
    for info in onScreenWindowInfo() {
      guard let metadata = windowMetadata(from: info),
        metadata.processIdentifier != excludedPID,
        DesktopGeometry.display(owning: metadata.frame)?.id == display.id,
        let running = NSRunningApplication(processIdentifier: metadata.processIdentifier),
        !running.isHidden,
        !running.isTerminated,
        let target = accessibilityTarget(matching: metadata),
        !isMinimized(target.element)
      else { continue }
      return target
    }
    return nil
  }

  @discardableResult
  func focus(_ target: AccessibilityTarget, warpPointerTo requestedPoint: CGPoint?) -> Bool {
    guard isTrusted else { return false }

    let application = AXUIElementCreateApplication(target.metadata.processIdentifier)
    if let running = NSRunningApplication(processIdentifier: target.metadata.processIdentifier) {
      running.activate()
    }

    _ = AXUIElementSetAttributeValue(
      application,
      kAXFocusedWindowAttribute as CFString,
      target.element
    )
    _ = AXUIElementSetAttributeValue(
      target.element,
      kAXFocusedAttribute as CFString,
      kCFBooleanTrue
    )
    let raised = AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)

    if let requestedPoint {
      let point = DesktopGeometry.clamp(requestedPoint, to: target.metadata.frame)
      CGWarpMouseCursorPosition(point)
    }
    return raised == .success
  }

  func warpPointer(to point: CGPoint) {
    CGWarpMouseCursorPosition(point)
  }

  private func metadata(for window: AXUIElement) -> TargetWindow? {
    var processIdentifier: pid_t = 0
    guard AXUIElementGetPid(window, &processIdentifier) == .success,
      let position = pointAttribute(window, kAXPositionAttribute as CFString),
      let size = sizeAttribute(window, kAXSizeAttribute as CFString)
    else {
      return nil
    }

    let title: String = copyAttribute(window, kAXTitleAttribute as CFString) ?? ""
    let frame = CGRect(origin: position, size: size)
    let identity = [
      String(processIdentifier),
      title,
      String(Int(frame.minX.rounded())),
      String(Int(frame.minY.rounded())),
      String(Int(frame.width.rounded())),
      String(Int(frame.height.rounded())),
    ].joined(separator: "|")

    return TargetWindow(
      processIdentifier: processIdentifier,
      frame: frame,
      title: title,
      identity: identity
    )
  }

  private func isMinimized(_ window: AXUIElement) -> Bool {
    copyAttribute(window, kAXMinimizedAttribute as CFString) ?? false
  }

  private func isOnCurrentSpace(_ metadata: TargetWindow) -> Bool {
    onScreenWindowInfo().contains { info in
      guard let candidate = windowMetadata(from: info) else { return false }
      return candidate.processIdentifier == metadata.processIdentifier
        && framesApproximatelyEqual(candidate.frame, metadata.frame)
    }
  }

  private func accessibilityTarget(matching expected: TargetWindow) -> AccessibilityTarget? {
    let application = AXUIElementCreateApplication(expected.processIdentifier)
    guard let windows: [AXUIElement] = copyAttribute(
      application, kAXWindowsAttribute as CFString)
    else { return nil }

    return windows.compactMap { window -> AccessibilityTarget? in
      guard let metadata = metadata(for: window),
        framesApproximatelyEqual(metadata.frame, expected.frame)
      else { return nil }
      return AccessibilityTarget(metadata: metadata, element: window)
    }.first
  }

  private func onScreenWindowInfo() -> [NSDictionary] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    return CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [NSDictionary] ?? []
  }

  private func windowMetadata(from info: NSDictionary) -> TargetWindow? {
    guard let layer = info[kCGWindowLayer] as? NSNumber, layer.intValue == 0,
      let alpha = info[kCGWindowAlpha] as? NSNumber, alpha.doubleValue > 0.01,
      let pid = info[kCGWindowOwnerPID] as? NSNumber,
      let boundsDictionary = info[kCGWindowBounds] as? NSDictionary,
      let frame = CGRect(dictionaryRepresentation: boundsDictionary),
      frame.width >= 80,
      frame.height >= 60
    else { return nil }

    let title = info[kCGWindowName] as? String ?? ""
    let processIdentifier = pid.int32Value
    let identity = [
      String(processIdentifier),
      title,
      String(Int(frame.minX.rounded())),
      String(Int(frame.minY.rounded())),
      String(Int(frame.width.rounded())),
      String(Int(frame.height.rounded())),
    ].joined(separator: "|")
    return TargetWindow(
      processIdentifier: processIdentifier,
      frame: frame,
      title: title,
      identity: identity
    )
  }

  private func framesApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    abs(lhs.minX - rhs.minX) <= 3
      && abs(lhs.minY - rhs.minY) <= 3
      && abs(lhs.width - rhs.width) <= 6
      && abs(lhs.height - rhs.height) <= 6
  }

  private func pointAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
    guard let value: AXValue = copyAttribute(element, attribute), AXValueGetType(value) == .cgPoint
    else {
      return nil
    }
    var point = CGPoint.zero
    return AXValueGetValue(value, .cgPoint, &point) ? point : nil
  }

  private func sizeAttribute(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
    guard let value: AXValue = copyAttribute(element, attribute), AXValueGetType(value) == .cgSize
    else {
      return nil
    }
    var size = CGSize.zero
    return AXValueGetValue(value, .cgSize, &size) ? size : nil
  }

  private func copyAttribute<T>(_ element: AXUIElement, _ attribute: CFString) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
      return nil
    }
    return value as? T
  }
}
