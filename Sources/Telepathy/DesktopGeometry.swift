import AppKit
import CoreGraphics

struct DisplayGeometry: Equatable {
  let vendor: UInt32
  let model: UInt32
  let serial: UInt32
  let isBuiltIn: Bool
  let isMain: Bool
  let bounds: CGRect
  let pixelWidth: Int
  let pixelHeight: Int
  let rotation: Int
}

struct ActiveDisplay: Equatable {
  let id: CGDirectDisplayID
  let bounds: CGRect
  let visibleBounds: CGRect
}

enum DesktopGeometry {
  static var activeDisplays: [ActiveDisplay] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }

    var displayIDs = Array(repeating: CGDirectDisplayID(), count: Int(count))
    guard CGGetActiveDisplayList(count, &displayIDs, &count) == .success else { return [] }

    return displayIDs.prefix(Int(count)).map { id in
      let bounds = CGDisplayBounds(id)
      let visibleBounds = NSScreen.screens.first(where: {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
          .uint32Value == id
      }).map { quartzRect(fromAppKit: $0.visibleFrame) } ?? bounds
      return ActiveDisplay(id: id, bounds: bounds, visibleBounds: visibleBounds)
    }
  }

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

  static var layoutFingerprint: String {
    fingerprint(for: activeDisplayGeometry)
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

  static func quartzRect(fromAppKit rect: CGRect) -> CGRect {
    CGRect(
      x: rect.minX,
      y: primaryDisplayHeight - rect.maxY,
      width: rect.width,
      height: rect.height
    )
  }

  static func quartzPoint(fromAppKit point: CGPoint) -> CGPoint {
    CGPoint(x: point.x, y: primaryDisplayHeight - point.y)
  }

  static func fingerprint(for displays: [DisplayGeometry]) -> String {
    let sortedDisplays = displays.sorted { left, right in
      if left.bounds.minX != right.bounds.minX { return left.bounds.minX < right.bounds.minX }
      if left.bounds.minY != right.bounds.minY { return left.bounds.minY < right.bounds.minY }
      return left.serial < right.serial
    }
    let descriptions: [String] = sortedDisplays.map { display in
      let fields = [
        String(display.vendor),
        String(display.model),
        String(display.serial),
        display.isBuiltIn ? "built-in" : "external",
        display.isMain ? "main" : "secondary",
        String(Int(display.bounds.minX.rounded())),
        String(Int(display.bounds.minY.rounded())),
        String(Int(display.bounds.width.rounded())),
        String(Int(display.bounds.height.rounded())),
        String(display.pixelWidth),
        String(display.pixelHeight),
        String(display.rotation),
      ]
      return fields.joined(separator: ":")
    }
    return descriptions.joined(separator: "|")
  }

  static func clamp(_ point: CGPoint, to rect: CGRect, inset: CGFloat = 8) -> CGPoint {
    let safe = rect.insetBy(dx: min(inset, rect.width / 4), dy: min(inset, rect.height / 4))
    return CGPoint(
      x: min(max(point.x, safe.minX), safe.maxX),
      y: min(max(point.y, safe.minY), safe.maxY)
    )
  }

  static func display(
    containing point: CGPoint,
    in displays: [ActiveDisplay] = activeDisplays
  ) -> ActiveDisplay? {
    displays.first(where: { $0.bounds.contains(point) })
  }

  static func display(
    owning rect: CGRect,
    in displays: [ActiveDisplay] = activeDisplays
  ) -> ActiveDisplay? {
    displays.max { left, right in
      intersectionArea(rect, left.bounds) < intersectionArea(rect, right.bounds)
    }.flatMap { intersectionArea(rect, $0.bounds) > 0 ? $0 : nil }
  }

  private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    let intersection = lhs.intersection(rhs)
    guard !intersection.isNull else { return 0 }
    return intersection.width * intersection.height
  }

  private static var primaryDisplayHeight: CGFloat {
    CGDisplayBounds(CGMainDisplayID()).height
  }

  private static var activeDisplayGeometry: [DisplayGeometry] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }

    var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
    guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }

    return displays.prefix(Int(count)).map { display in
      DisplayGeometry(
        vendor: CGDisplayVendorNumber(display),
        model: CGDisplayModelNumber(display),
        serial: CGDisplaySerialNumber(display),
        isBuiltIn: CGDisplayIsBuiltin(display) != 0,
        isMain: CGDisplayIsMain(display) != 0,
        bounds: CGDisplayBounds(display),
        pixelWidth: CGDisplayPixelsWide(display),
        pixelHeight: CGDisplayPixelsHigh(display),
        rotation: Int(CGDisplayRotation(display).rounded())
      )
    }
  }
}
