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
    drawPeripheralMark(in: markRect)
  }

  private func drawPeripheralMark(in rect: NSRect) {
    let scale = rect.width / 64
    let point: (CGFloat, CGFloat) -> NSPoint = { x, y in
      NSPoint(x: rect.minX + x * scale, y: rect.maxY - y * scale)
    }

    accentColor.setStroke()
    let brackets = NSBezierPath()
    brackets.lineWidth = 5 * scale
    brackets.lineCapStyle = .round
    brackets.lineJoinStyle = .round
    brackets.move(to: point(20, 12))
    brackets.line(to: point(9, 12))
    brackets.line(to: point(9, 52))
    brackets.line(to: point(20, 52))
    brackets.move(to: point(44, 12))
    brackets.line(to: point(55, 12))
    brackets.line(to: point(55, 52))
    brackets.line(to: point(44, 52))
    brackets.stroke()

    let eye = NSBezierPath()
    eye.lineWidth = 4 * scale
    eye.lineJoinStyle = .round
    eye.move(to: point(18, 32))
    eye.curve(
      to: point(36, 20),
      controlPoint1: point(23, 24),
      controlPoint2: point(29, 20)
    )
    eye.curve(
      to: point(54, 32),
      controlPoint1: point(43, 20),
      controlPoint2: point(49, 24)
    )
    eye.curve(
      to: point(36, 44),
      controlPoint1: point(49, 40),
      controlPoint2: point(43, 44)
    )
    eye.curve(
      to: point(18, 32),
      controlPoint1: point(29, 44),
      controlPoint2: point(23, 40)
    )
    eye.close()
    eye.stroke()

    accentColor.setFill()
    let pupilRadius = 6 * scale
    let pupilCenter = point(40, 32)
    let pupil = NSRect(
      x: pupilCenter.x - pupilRadius,
      y: pupilCenter.y - pupilRadius,
      width: pupilRadius * 2,
      height: pupilRadius * 2
    )
    NSBezierPath(ovalIn: pupil).fill()
  }
}
