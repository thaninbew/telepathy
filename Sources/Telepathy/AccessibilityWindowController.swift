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
  private let systemWide = AXUIElementCreateSystemWide()

  var isTrusted: Bool { AXIsProcessTrusted() }

  func openTrustSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    else { return }
    NSWorkspace.shared.open(url)
  }

  func window(at point: CGPoint) -> AccessibilityTarget? {
    var hitElement: AXUIElement?
    let result = AXUIElementCopyElementAtPosition(
      systemWide,
      Float(point.x),
      Float(point.y),
      &hitElement
    )
    guard result == .success, let hitElement else { return nil }

    let window = containingWindow(for: hitElement) ?? hitElement
    guard role(of: window) == kAXWindowRole as String,
      let metadata = metadata(for: window)
    else {
      return nil
    }
    return AccessibilityTarget(metadata: metadata, element: window)
  }

  func focusedWindowIdentity() -> String? {
    guard let running = NSWorkspace.shared.frontmostApplication else { return nil }
    let application = AXUIElementCreateApplication(running.processIdentifier)
    guard
      let focused: AXUIElement = copyAttribute(application, kAXFocusedWindowAttribute as CFString),
      let metadata = metadata(for: focused)
    else {
      return nil
    }
    return metadata.identity
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

  private func containingWindow(for element: AXUIElement) -> AXUIElement? {
    if let window: AXUIElement = copyAttribute(element, kAXWindowAttribute as CFString) {
      return window
    }

    var current: AXUIElement? = element
    for _ in 0..<12 {
      guard let value = current else { return nil }
      if role(of: value) == kAXWindowRole as String { return value }
      current = copyAttribute(value, kAXParentAttribute as CFString)
    }
    return nil
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

  private func role(of element: AXUIElement) -> String? {
    copyAttribute(element, kAXRoleAttribute as CFString)
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
