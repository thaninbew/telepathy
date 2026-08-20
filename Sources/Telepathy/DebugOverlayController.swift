import AppKit
import CoreGraphics
import Foundation

enum DisplayFeedbackPhase: Equatable {
  case candidate
  case holding(progress: Double)
  case confirmed(progress: Double)
}

@MainActor
final class DebugOverlayController {
  private struct Surface {
    let panel: NSPanel
    let view: DebugOverlayView
  }

  private var surfaces: [Surface] = []
  private var indicatorSmoother = GazeIndicatorSmoother()
  private var screenObserver: NSObjectProtocol?
  private var snapshot = DebugOverlaySnapshot(
    indicatorPoint: nil,
    displayFrame: nil,
    feedbackPhase: nil,
    accentColor: OverlayStyle.accent
  )

  var accentColor = OverlayStyle.accent {
    didSet {
      guard !accentColor.isEqual(oldValue) else { return }
      snapshot.accentColor = accentColor
      applySnapshot()
    }
  }

  var isVisible = true {
    didSet {
      guard oldValue != isVisible else { return }
      updateVisibility()
    }
  }

  init() {
    rebuildSurfaces()

    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.rebuildSurfaces()
      }
    }
  }

  func show() {
    updateVisibility()
  }

  func update(
    gazePoint: CGPoint?,
    displayFrame: CGRect?,
    feedbackPhase: DisplayFeedbackPhase?
  ) {
    let indicatorPoint: CGPoint?
    if let gazePoint {
      let appKitPoint = DesktopGeometry.appKitPoint(fromQuartz: gazePoint)
      indicatorPoint = indicatorSmoother.update(with: appKitPoint)
    } else {
      indicatorSmoother.reset()
      indicatorPoint = nil
    }

    snapshot = DebugOverlaySnapshot(
      indicatorPoint: indicatorPoint,
      displayFrame: displayFrame.map(DesktopGeometry.appKitRect(fromQuartz:)),
      feedbackPhase: feedbackPhase,
      accentColor: accentColor
    )
    applySnapshot()
  }

  private func rebuildSurfaces() {
    indicatorSmoother.reset()
    surfaces.forEach { $0.panel.orderOut(nil) }
    surfaces = NSScreen.screens.map { screen in
      let view = DebugOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
      let panel = NSPanel(
        contentRect: screen.frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false,
        screen: screen
      )
      panel.setFrame(screen.frame, display: false)
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      panel.ignoresMouseEvents = true
      panel.hidesOnDeactivate = false
      panel.level = .statusBar
      panel.collectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
      ]
      panel.contentView = view
      panel.setAccessibilityElement(false)
      view.setAccessibilityElement(false)
      return Surface(panel: panel, view: view)
    }
    applySnapshot()
    updateVisibility()
  }

  private func applySnapshot() {
    for surface in surfaces {
      surface.view.snapshot = snapshot
      surface.view.needsDisplay = true
    }
  }

  private func updateVisibility() {
    if isVisible {
      surfaces.forEach { $0.panel.orderFrontRegardless() }
    } else {
      surfaces.forEach { $0.panel.orderOut(nil) }
    }
  }
}

private struct DebugOverlaySnapshot {
  var indicatorPoint: CGPoint?
  var displayFrame: CGRect?
  var feedbackPhase: DisplayFeedbackPhase?
  var accentColor: NSColor
}

struct EdgeBloomMetrics: Equatable {
  let depth: Double
  let edgeAlpha: Double
  let middleAlpha: Double
  let hairlineAlpha: Double

  static func resolve(_ phase: DisplayFeedbackPhase) -> EdgeBloomMetrics {
    switch phase {
    case .candidate:
      return EdgeBloomMetrics(depth: 8, edgeAlpha: 0.12, middleAlpha: 0.04, hairlineAlpha: 0.18)
    case .holding(let value):
      let progress = min(max(value, 0), 1)
      return EdgeBloomMetrics(
        depth: 8 + 20 * progress,
        edgeAlpha: 0.10 + 0.12 * progress,
        middleAlpha: 0.035 + 0.045 * progress,
        hairlineAlpha: 0.16 + 0.12 * progress
      )
    case .confirmed(let value):
      let progress = min(max(value, 0), 1)
      let fadeIn = min(progress / 0.28, 1)
      let fadeOut = max(1 - max(progress - 0.28, 0) / 0.72, 0)
      let intensity = fadeIn * fadeOut
      return EdgeBloomMetrics(
        depth: 6 + 22 * Self.easeOutCubic(progress),
        edgeAlpha: 0.24 * intensity,
        middleAlpha: 0.085 * intensity,
        hairlineAlpha: 0.32 * intensity
      )
    }
  }

  private static func easeOutCubic(_ value: Double) -> Double {
    1 - pow(1 - value, 3)
  }
}

private final class DebugOverlayView: NSView {
  var snapshot = DebugOverlaySnapshot(
    indicatorPoint: nil,
    displayFrame: nil,
    feedbackPhase: nil,
    accentColor: OverlayStyle.accent
  )

  override var isFlipped: Bool { false }
  override var acceptsFirstResponder: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let context = NSGraphicsContext.current?.cgContext else { return }

    context.saveGState()
    defer { context.restoreGState() }

    if let displayFrame = snapshot.displayFrame, let phase = snapshot.feedbackPhase {
      drawDisplayBloom(globalFrame: displayFrame, phase: phase, context: context)
    }
    if let indicatorPoint = snapshot.indicatorPoint {
      drawGazeIndicator(globalPoint: indicatorPoint, context: context)
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

  private func drawDisplayBloom(
    globalFrame: CGRect,
    phase: DisplayFeedbackPhase,
    context: CGContext
  ) {
    let frame = local(globalFrame).intersection(bounds)
    guard !frame.isNull, frame.width > 1, frame.height > 1 else { return }

    let metrics = EdgeBloomMetrics.resolve(phase)
    let depth = CGFloat(min(metrics.depth, Double(min(frame.width, frame.height) / 3)))
    let accent = snapshot.accentColor
    guard
      let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
          accent.withAlphaComponent(metrics.edgeAlpha).cgColor,
          accent.withAlphaComponent(metrics.middleAlpha).cgColor,
          accent.withAlphaComponent(0).cgColor,
        ] as CFArray,
        locations: [0, 0.36, 1]
      )
    else { return }

    drawEdgeGradient(
      in: CGRect(x: frame.minX, y: frame.maxY - depth, width: frame.width, height: depth),
      from: CGPoint(x: frame.midX, y: frame.maxY),
      to: CGPoint(x: frame.midX, y: frame.maxY - depth),
      gradient: gradient,
      context: context
    )
    drawEdgeGradient(
      in: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: depth),
      from: CGPoint(x: frame.midX, y: frame.minY),
      to: CGPoint(x: frame.midX, y: frame.minY + depth),
      gradient: gradient,
      context: context
    )
    drawEdgeGradient(
      in: CGRect(x: frame.minX, y: frame.minY, width: depth, height: frame.height),
      from: CGPoint(x: frame.minX, y: frame.midY),
      to: CGPoint(x: frame.minX + depth, y: frame.midY),
      gradient: gradient,
      context: context
    )
    drawEdgeGradient(
      in: CGRect(x: frame.maxX - depth, y: frame.minY, width: depth, height: frame.height),
      from: CGPoint(x: frame.maxX, y: frame.midY),
      to: CGPoint(x: frame.maxX - depth, y: frame.midY),
      gradient: gradient,
      context: context
    )

    context.setStrokeColor(accent.withAlphaComponent(metrics.hairlineAlpha).cgColor)
    context.setLineWidth(1)
    context.stroke(frame.insetBy(dx: 0.5, dy: 0.5))
  }

  private func drawEdgeGradient(
    in rect: CGRect,
    from start: CGPoint,
    to end: CGPoint,
    gradient: CGGradient,
    context: CGContext
  ) {
    context.saveGState()
    context.clip(to: rect)
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
    context.restoreGState()
  }

  private func drawGazeIndicator(globalPoint: CGPoint, context: CGContext) {
    let point = local(globalPoint)
    let area = CGRect(
      x: point.x - OverlayStyle.indicatorRadius,
      y: point.y - OverlayStyle.indicatorRadius,
      width: OverlayStyle.indicatorRadius * 2,
      height: OverlayStyle.indicatorRadius * 2
    )
    context.setStrokeColor(snapshot.accentColor.withAlphaComponent(0.58).cgColor)
    context.setLineWidth(OverlayStyle.indicatorLineWidth)
    context.strokeEllipse(in: area)

    let center = CGRect(
      x: point.x - OverlayStyle.indicatorCenterRadius,
      y: point.y - OverlayStyle.indicatorCenterRadius,
      width: OverlayStyle.indicatorCenterRadius * 2,
      height: OverlayStyle.indicatorCenterRadius * 2
    )
    context.setFillColor(snapshot.accentColor.cgColor)
    context.fillEllipse(in: center)
  }
}
