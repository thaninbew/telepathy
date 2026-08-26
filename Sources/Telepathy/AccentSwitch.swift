import AppKit

final class AccentSwitch: NSButton {
  var accentColor = OverlayStyle.accent {
    didSet {
      guard !accentColor.isEqual(oldValue) else { return }
      needsDisplay = true
    }
  }

  override var state: NSControl.StateValue {
    didSet {
      needsDisplay = true
      setAccessibilityValue(state == .on ? 1 : 0)
    }
  }

  override var intrinsicContentSize: NSSize {
    NSSize(width: 42, height: 24)
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setButtonType(.toggle)
    title = ""
    isBordered = false
    focusRingType = .exterior
    setAccessibilityRole(.checkBox)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func draw(_ dirtyRect: NSRect) {
    let track = bounds.insetBy(dx: 1, dy: 2)
    let trackColor = state == .on
      ? accentColor.withAlphaComponent(isHighlighted ? 0.78 : 0.94)
      : OverlayStyle.idle.withAlphaComponent(isHighlighted ? 0.32 : 0.24)
    trackColor.setFill()
    NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2).fill()

    let knobSize = track.height - 4
    let knobX = state == .on ? track.maxX - knobSize - 2 : track.minX + 2
    let knob = NSRect(x: knobX, y: track.minY + 2, width: knobSize, height: knobSize)
    OverlayStyle.text.withAlphaComponent(isEnabled ? 0.96 : 0.48).setFill()
    NSBezierPath(ovalIn: knob).fill()

    if window?.firstResponder === self {
      NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.72).setStroke()
      let focus = NSBezierPath(
        roundedRect: track.insetBy(dx: -2, dy: -2),
        xRadius: track.height / 2 + 2,
        yRadius: track.height / 2 + 2
      )
      focus.lineWidth = 2
      focus.stroke()
    }
  }
}
