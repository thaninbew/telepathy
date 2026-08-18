import AppKit
import CoreGraphics
import Foundation

@MainActor
final class DebugOverlayController {
  private let panel: NSPanel
  private let overlayView: DebugOverlayView
  private var screenObserver: NSObjectProtocol?

  var isVisible = true {
    didSet {
      guard oldValue != isVisible else { return }
      updateVisibility()
    }
  }

  init() {
    let frame = DesktopGeometry.appKitBounds
    overlayView = DebugOverlayView(frame: CGRect(origin: .zero, size: frame.size))
    panel = NSPanel(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.level = .statusBar
    panel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    panel.contentView = overlayView
    panel.setAccessibilityElement(false)
    overlayView.setAccessibilityElement(false)

    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.refreshDesktopFrame()
      }
    }
  }

  func show() {
    updateVisibility()
  }

  func update(
    rawPoint: CGPoint?,
    smoothedPoint: CGPoint?,
    targetFrame: CGRect?
  ) {
    overlayView.snapshot = DebugOverlaySnapshot(
      rawPoint: rawPoint.map(DesktopGeometry.appKitPoint(fromQuartz:)),
      smoothedPoint: smoothedPoint.map(DesktopGeometry.appKitPoint(fromQuartz:)),
      targetFrame: targetFrame.map(DesktopGeometry.appKitRect(fromQuartz:))
    )
    overlayView.needsDisplay = true
  }

  private func refreshDesktopFrame() {
    let frame = DesktopGeometry.appKitBounds
    panel.setFrame(frame, display: true)
    overlayView.frame = CGRect(origin: .zero, size: frame.size)
  }

  private func updateVisibility() {
    if isVisible {
      panel.orderFrontRegardless()
    } else {
      panel.orderOut(nil)
    }
  }
}

private struct DebugOverlaySnapshot {
  var rawPoint: CGPoint?
  var smoothedPoint: CGPoint?
  var targetFrame: CGRect?
}

private final class DebugOverlayView: NSView {
  var snapshot = DebugOverlaySnapshot(
    rawPoint: nil,
    smoothedPoint: nil,
    targetFrame: nil
  )

  override var isFlipped: Bool { false }
  override var acceptsFirstResponder: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let context = NSGraphicsContext.current?.cgContext else { return }

    context.saveGState()
    defer { context.restoreGState() }

    if let targetFrame = snapshot.targetFrame {
      drawTargetWindow(globalFrame: targetFrame, context: context)
    }
    if let rawPoint = snapshot.rawPoint {
      drawRawSignal(globalPoint: rawPoint, context: context)
    }
    if let smoothedPoint = snapshot.smoothedPoint {
      drawGazeMarker(globalPoint: smoothedPoint, context: context)
    }
  }

  private func local(_ globalPoint: CGPoint) -> CGPoint {
    CGPoint(x: globalPoint.x - windowFrame.minX, y: globalPoint.y - windowFrame.minY)
  }

  private func local(_ globalRect: CGRect) -> CGRect {
    CGRect(
      x: globalRect.minX - windowFrame.minX,
      y: globalRect.minY - windowFrame.minY,
      width: globalRect.width,
      height: globalRect.height
    )
  }

  private var windowFrame: CGRect {
    window?.frame ?? DesktopGeometry.appKitBounds
  }

  private func drawTargetWindow(globalFrame: CGRect, context: CGContext) {
    let frame = local(globalFrame).insetBy(dx: 2, dy: 2)
    let path = CGPath(
      roundedRect: frame,
      cornerWidth: OverlayStyle.windowCornerRadius,
      cornerHeight: OverlayStyle.windowCornerRadius,
      transform: nil
    )

    context.addPath(path)
    context.setStrokeColor(OverlayStyle.ink.withAlphaComponent(0.72).cgColor)
    context.setLineWidth(4)
    context.strokePath()

    context.addPath(path)
    context.setStrokeColor(OverlayStyle.accentMuted.cgColor)
    context.setLineWidth(1.25)
    context.strokePath()
  }

  private func drawRawSignal(globalPoint: CGPoint, context: CGContext) {
    let point = local(globalPoint)
    context.setStrokeColor(OverlayStyle.rawSignal.cgColor)
    context.setLineWidth(1)
    context.move(to: CGPoint(x: point.x - 4, y: point.y))
    context.addLine(to: CGPoint(x: point.x + 4, y: point.y))
    context.move(to: CGPoint(x: point.x, y: point.y - 4))
    context.addLine(to: CGPoint(x: point.x, y: point.y + 4))
    context.strokePath()
  }

  private func drawGazeMarker(globalPoint: CGPoint, context: CGContext) {
    let point = local(globalPoint)
    let halo = CGRect(
      x: point.x - OverlayStyle.markerHaloRadius,
      y: point.y - OverlayStyle.markerHaloRadius,
      width: OverlayStyle.markerHaloRadius * 2,
      height: OverlayStyle.markerHaloRadius * 2
    )
    context.setFillColor(OverlayStyle.accentFaint.cgColor)
    context.fillEllipse(in: halo)

    let marker = CGRect(
      x: point.x - OverlayStyle.markerRadius,
      y: point.y - OverlayStyle.markerRadius,
      width: OverlayStyle.markerRadius * 2,
      height: OverlayStyle.markerRadius * 2
    )
    context.setFillColor(OverlayStyle.accent.cgColor)
    context.fillEllipse(in: marker)
    context.setStrokeColor(OverlayStyle.ink.cgColor)
    context.setLineWidth(1)
    context.strokeEllipse(in: marker)
  }

}
