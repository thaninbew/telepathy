import AppKit
import CoreGraphics

enum DesktopGeometry {
  static var quartzBounds: CGRect {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
      return CGDisplayBounds(CGMainDisplayID())
    }

    var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
    guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
      return CGDisplayBounds(CGMainDisplayID())
    }

    return displays.prefix(Int(count))
      .map(CGDisplayBounds)
      .reduce(CGRect.null) { $0.union($1) }
  }

  static var appKitBounds: CGRect {
    appKitRect(fromQuartz: quartzBounds)
  }

  static func appKitPoint(fromQuartz point: CGPoint) -> CGPoint {
    CGPoint(x: point.x, y: primaryDisplayHeight - point.y)
  }

  static func appKitRect(fromQuartz rect: CGRect) -> CGRect {
    CGRect(
      x: rect.minX,
      y: primaryDisplayHeight - rect.maxY,
      width: rect.width,
      height: rect.height
    )
  }

  static func clamp(_ point: CGPoint, to rect: CGRect, inset: CGFloat = 8) -> CGPoint {
    let safe = rect.insetBy(dx: min(inset, rect.width / 4), dy: min(inset, rect.height / 4))
    return CGPoint(
      x: min(max(point.x, safe.minX), safe.maxX),
      y: min(max(point.y, safe.minY), safe.maxY)
    )
  }

  private static var primaryDisplayHeight: CGFloat {
    CGDisplayBounds(CGMainDisplayID()).height
  }
}
