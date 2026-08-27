import AppKit

final class TelepathyLogoView: NSView {
  var accentColor: NSColor = .controlAccentColor {
    didSet { needsDisplay = true }
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: TelepathyComponent.logoSize, height: TelepathyComponent.logoSize)
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = TelepathySemantic.raised.cgColor
    layer?.borderColor = TelepathySemantic.border.cgColor
    layer?.borderWidth = TelepathyComponent.dividerWidth
    layer?.cornerRadius = TelepathyComponent.iconRadius
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    layer?.backgroundColor = TelepathySemantic.raised.cgColor
    layer?.borderColor = TelepathySemantic.border.cgColor
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let markSize = TelepathyComponent.logoMarkSize
    let markRect = NSRect(
      x: bounds.midX - markSize.width / 2,
      y: bounds.midY - markSize.height / 2,
      width: markSize.width,
      height: markSize.height
    )
    Self.drawSentinelMark(in: markRect, color: accentColor)
  }

  static func statusItemImage() -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
      drawSentinelMark(in: rect, color: .labelColor)
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Telepathy"
    return image
  }

  private static func drawSentinelMark(in rect: NSRect, color: NSColor) {
    let scale = rect.width / 64
    let point: (CGFloat, CGFloat) -> NSPoint = { x, y in
      NSPoint(x: rect.minX + x * scale, y: rect.maxY - y * scale)
    }

    color.setFill()
    let body = NSBezierPath()
    body.windingRule = .evenOdd
    body.move(to: point(32, 3))
    body.line(to: point(57, 15.5))
    body.line(to: point(57, 40.5))
    body.line(to: point(45.3, 51))
    body.line(to: point(32, 61))
    body.line(to: point(18.7, 51))
    body.line(to: point(7, 40.5))
    body.line(to: point(7, 15.5))
    body.close()
    body.move(to: point(32, 18.2))
    body.line(to: point(14.5, 31.2))
    body.line(to: point(25, 42.8))
    body.line(to: point(39, 42.8))
    body.line(to: point(49.5, 31.2))
    body.close()
    body.fill()

    let pupilRadius = 6.4 * scale
    let pupilCenter = point(32, 31.2)
    let pupil = NSRect(
      x: pupilCenter.x - pupilRadius,
      y: pupilCenter.y - pupilRadius,
      width: pupilRadius * 2,
      height: pupilRadius * 2
    )
    NSBezierPath(ovalIn: pupil).fill()
  }
}
