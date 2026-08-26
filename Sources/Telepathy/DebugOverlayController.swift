import AppKit
import CoreGraphics
import Foundation
import QuartzCore

enum DisplayFeedbackPhase: Equatable {
  case candidate
  case holding(progress: Double)
  case confirmed(progress: Double)
}

@MainActor
final class DebugOverlayController {
  private var surfaces: [DisplayShineSurface] = []
  private var indicatorSurface: GazeIndicatorSurface?
  private var indicatorSmoother = GazeIndicatorSmoother()
  private var screenObserver: NSObjectProtocol?
  private var indicatorPoint: CGPoint?
  private var feedbackDisplayFrame: CGRect?
  private var feedbackPhase: DisplayFeedbackPhase?

  var accentColor = OverlayStyle.accent {
    didSet {
      guard !accentColor.isEqual(oldValue) else { return }
      renderCurrentState()
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

    self.indicatorPoint = indicatorPoint
    feedbackDisplayFrame = displayFrame.map(DesktopGeometry.appKitRect(fromQuartz:))
    self.feedbackPhase = feedbackPhase
    renderCurrentState()
  }

  private func rebuildSurfaces() {
    indicatorSmoother.reset()
    indicatorPoint = nil
    feedbackDisplayFrame = nil
    feedbackPhase = nil
    for surface in surfaces { surface.hide() }
    indicatorSurface?.hide()
    indicatorSurface = nil
    surfaces = NSScreen.screens.map(DisplayShineSurface.init(screen:))
    updateVisibility()
  }

  private func renderCurrentState() {
    guard isVisible else { return }
    renderShine()
    renderIndicator()
  }

  private func updateVisibility() {
    if isVisible {
      renderCurrentState()
    } else {
      for surface in surfaces { surface.hide() }
      indicatorSurface?.hide()
    }
  }

  private func renderShine() {
    guard
      let feedbackDisplayFrame,
      let feedbackPhase,
      let target = targetSurface(for: feedbackDisplayFrame)
    else {
      for surface in surfaces { surface.hide() }
      return
    }

    let metrics = EdgeBloomMetrics.resolve(feedbackPhase)
    for surface in surfaces {
      if surface === target {
        surface.show(metrics: metrics, accentColor: accentColor)
      } else {
        surface.hide()
      }
    }
  }

  private func renderIndicator() {
    guard let indicatorPoint else {
      indicatorSurface?.hide()
      return
    }

    if indicatorSurface == nil {
      let screen =
        NSScreen.screens.first(where: { $0.frame.contains(indicatorPoint) })
        ?? NSScreen.main
        ?? NSScreen.screens.first
      guard let screen else { return }
      indicatorSurface = GazeIndicatorSurface(screen: screen)
    }
    indicatorSurface?.show(at: indicatorPoint, accentColor: accentColor)
  }

  private func targetSurface(for displayFrame: CGRect) -> DisplayShineSurface? {
    let matches = surfaces.map { surface in
      let intersection = surface.displayFrame.intersection(displayFrame)
      let area = intersection.isNull ? 0 : intersection.width * intersection.height
      return (surface, area)
    }
    guard let match = matches.max(by: { $0.1 < $1.1 }), match.1 > 1 else {
      return nil
    }
    return match.0
  }
}

struct EdgeBloomMetrics: Equatable {
  static let maximumDepth = 56.0

  let depth: Double
  let opacity: Double

  static func resolve(_ phase: DisplayFeedbackPhase) -> EdgeBloomMetrics {
    switch phase {
    case .candidate:
      return EdgeBloomMetrics(depth: 24, opacity: 0.16)
    case .holding(let value):
      let progress = min(max(value, 0), 1)
      let easedProgress = Self.easeOutCubic(progress)
      return EdgeBloomMetrics(
        depth: 24 + 28 * easedProgress,
        opacity: 0.15 + 0.13 * easedProgress
      )
    case .confirmed(let value):
      let progress = min(max(value, 0), 1)
      let fadeIn = min(progress / 0.24, 1)
      let fadeOut = max(1 - max(progress - 0.24, 0) / 0.76, 0)
      let intensity = fadeIn * fadeOut
      return EdgeBloomMetrics(
        depth: 22 + 34 * Self.easeOutCubic(progress),
        opacity: 0.34 * intensity
      )
    }
  }

  private static func easeOutCubic(_ value: Double) -> Double {
    1 - pow(1 - value, 3)
  }
}

struct EdgeShineGradientSpec: Equatable {
  let locations: [Double]
  let relativeAlphas: [Double]

  static let standard = EdgeShineGradientSpec(
    locations: [0, 0.08, 0.26, 0.58, 1],
    relativeAlphas: [0.72, 1, 0.58, 0.18, 0]
  )
}

struct EdgeStripFrames: Equatable {
  let top: CGRect
  let bottom: CGRect
  let left: CGRect
  let right: CGRect

  static func resolve(
    displayFrame: CGRect,
    maximumDepth: CGFloat = EdgeBloomMetrics.maximumDepth
  ) -> EdgeStripFrames {
    let depth = min(maximumDepth, min(displayFrame.width, displayFrame.height) / 3)
    let sideHeight = max(displayFrame.height - 2 * depth, 0)
    return EdgeStripFrames(
      top: CGRect(
        x: displayFrame.minX,
        y: displayFrame.maxY - depth,
        width: displayFrame.width,
        height: depth
      ),
      bottom: CGRect(
        x: displayFrame.minX,
        y: displayFrame.minY,
        width: displayFrame.width,
        height: depth
      ),
      left: CGRect(
        x: displayFrame.minX,
        y: displayFrame.minY + depth,
        width: depth,
        height: sideHeight
      ),
      right: CGRect(
        x: displayFrame.maxX - depth,
        y: displayFrame.minY + depth,
        width: depth,
        height: sideHeight
      )
    )
  }
}

private enum ShineEdge {
  case top
  case bottom
  case left
  case right
}

@MainActor
private final class DisplayShineSurface {
  let displayFrame: CGRect
  private let strips: [EdgeShineSurface]

  init(screen: NSScreen) {
    displayFrame = screen.frame
    let frames = EdgeStripFrames.resolve(displayFrame: screen.frame)
    strips = [
      EdgeShineSurface(frame: frames.top, edge: .top, screen: screen),
      EdgeShineSurface(frame: frames.bottom, edge: .bottom, screen: screen),
      EdgeShineSurface(frame: frames.left, edge: .left, screen: screen),
      EdgeShineSurface(frame: frames.right, edge: .right, screen: screen),
    ]
  }

  func show(metrics: EdgeBloomMetrics, accentColor: NSColor) {
    for strip in strips { strip.show(metrics: metrics, accentColor: accentColor) }
  }

  func hide() {
    for strip in strips { strip.hide() }
  }
}

@MainActor
private final class EdgeShineSurface {
  private let panel: NSPanel
  private let view: EdgeShineView

  init(frame: CGRect, edge: ShineEdge, screen: NSScreen) {
    view = EdgeShineView(frame: CGRect(origin: .zero, size: frame.size), edge: edge)
    panel = makeOverlayPanel(frame: frame, screen: screen, contentView: view)
  }

  func show(metrics: EdgeBloomMetrics, accentColor: NSColor) {
    view.apply(metrics: metrics, accentColor: accentColor)
    if metrics.opacity > 0 {
      if !panel.isVisible { panel.orderFrontRegardless() }
    } else if panel.isVisible {
      panel.orderOut(nil)
    }
  }

  func hide() {
    if panel.isVisible { panel.orderOut(nil) }
    view.suspendRendering()
  }
}

private final class EdgeShineView: NSView {
  private let edge: ShineEdge
  private let shineLayer = CAGradientLayer()
  private var gradientAccent: NSColor?
  private var renderedMetrics: EdgeBloomMetrics?
  private var shineIsHidden = true

  override var isFlipped: Bool { false }
  override var acceptsFirstResponder: Bool { false }

  init(frame frameRect: NSRect, edge: ShineEdge) {
    self.edge = edge
    super.init(frame: frameRect)
    configureLayer()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(metrics: EdgeBloomMetrics, accentColor: NSColor) {
    updateGradientColorsIfNeeded(accentColor)
    guard shineIsHidden || renderedMetrics != metrics else { return }
    renderedMetrics = metrics

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layoutShineLayer(depth: CGFloat(metrics.depth))
    shineLayer.opacity = Float(metrics.opacity)
    shineLayer.isHidden = metrics.opacity <= 0
    shineIsHidden = metrics.opacity <= 0
    CATransaction.commit()
  }

  func suspendRendering() {
    guard !shineIsHidden else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    shineLayer.isHidden = true
    shineLayer.opacity = 0
    shineIsHidden = true
    CATransaction.commit()
  }

  override func layout() {
    super.layout()
    guard let renderedMetrics else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layoutShineLayer(depth: CGFloat(renderedMetrics.depth))
    CATransaction.commit()
  }

  private func configureLayer() {
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor

    switch edge {
    case .top:
      shineLayer.startPoint = CGPoint(x: 0.5, y: 1)
      shineLayer.endPoint = CGPoint(x: 0.5, y: 0)
    case .bottom:
      shineLayer.startPoint = CGPoint(x: 0.5, y: 0)
      shineLayer.endPoint = CGPoint(x: 0.5, y: 1)
    case .left:
      shineLayer.startPoint = CGPoint(x: 0, y: 0.5)
      shineLayer.endPoint = CGPoint(x: 1, y: 0.5)
    case .right:
      shineLayer.startPoint = CGPoint(x: 1, y: 0.5)
      shineLayer.endPoint = CGPoint(x: 0, y: 0.5)
    }

    shineLayer.locations = EdgeShineGradientSpec.standard.locations.map { NSNumber(value: $0) }
    shineLayer.isHidden = true
    shineLayer.opacity = 0
    layer?.addSublayer(shineLayer)
  }

  private func updateGradientColorsIfNeeded(_ accent: NSColor) {
    guard gradientAccent?.isEqual(accent) != true else { return }
    gradientAccent = accent

    let base = accent.usingColorSpace(.deviceRGB) ?? accent
    let highlight = base.blended(withFraction: 0.18, of: .white) ?? base
    let softHighlight = base.blended(withFraction: 0.08, of: .white) ?? base
    let tones = [highlight, softHighlight, base, base, base]
    let colors = zip(tones, EdgeShineGradientSpec.standard.relativeAlphas).map { tone, alpha in
      tone.withAlphaComponent(alpha).cgColor
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    shineLayer.colors = colors
    CATransaction.commit()
  }

  private func layoutShineLayer(depth requestedDepth: CGFloat) {
    let maximumDepth: CGFloat
    switch edge {
    case .top, .bottom:
      maximumDepth = bounds.height
    case .left, .right:
      maximumDepth = bounds.width
    }
    let depth = min(requestedDepth, maximumDepth)
    switch edge {
    case .top:
      shineLayer.frame = CGRect(x: 0, y: bounds.maxY - depth, width: bounds.width, height: depth)
    case .bottom:
      shineLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: depth)
    case .left:
      shineLayer.frame = CGRect(x: 0, y: 0, width: depth, height: bounds.height)
    case .right:
      shineLayer.frame = CGRect(x: bounds.maxX - depth, y: 0, width: depth, height: bounds.height)
    }
  }
}

@MainActor
private final class GazeIndicatorSurface {
  private static let diameter = ceil(
    2 * (OverlayStyle.indicatorRadius + OverlayStyle.indicatorLineWidth + 2)
  )

  private let panel: NSPanel
  private let view: GazeIndicatorView
  private var renderedFrame: CGRect?

  init(screen: NSScreen) {
    let size = CGSize(width: Self.diameter, height: Self.diameter)
    view = GazeIndicatorView(frame: CGRect(origin: .zero, size: size))
    panel = makeOverlayPanel(
      frame: CGRect(origin: screen.frame.origin, size: size),
      screen: screen,
      contentView: view
    )
  }

  func show(at point: CGPoint, accentColor: NSColor) {
    view.accentColor = accentColor
    let frame = CGRect(
      x: point.x - Self.diameter / 2,
      y: point.y - Self.diameter / 2,
      width: Self.diameter,
      height: Self.diameter
    )
    if renderedFrame != frame {
      panel.setFrame(frame, display: false)
      renderedFrame = frame
    }
    if !panel.isVisible { panel.orderFrontRegardless() }
  }

  func hide() {
    if panel.isVisible { panel.orderOut(nil) }
  }
}

private final class GazeIndicatorView: NSView {
  var accentColor = OverlayStyle.accent {
    didSet {
      guard !accentColor.isEqual(oldValue) else { return }
      needsDisplay = true
    }
  }

  override var isFlipped: Bool { false }
  override var acceptsFirstResponder: Bool { false }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let point = CGPoint(x: bounds.midX, y: bounds.midY)
    let area = CGRect(
      x: point.x - OverlayStyle.indicatorRadius,
      y: point.y - OverlayStyle.indicatorRadius,
      width: OverlayStyle.indicatorRadius * 2,
      height: OverlayStyle.indicatorRadius * 2
    )
    context.setStrokeColor(accentColor.withAlphaComponent(0.58).cgColor)
    context.setLineWidth(OverlayStyle.indicatorLineWidth)
    context.strokeEllipse(in: area)

    let center = CGRect(
      x: point.x - OverlayStyle.indicatorCenterRadius,
      y: point.y - OverlayStyle.indicatorCenterRadius,
      width: OverlayStyle.indicatorCenterRadius * 2,
      height: OverlayStyle.indicatorCenterRadius * 2
    )
    context.setFillColor(accentColor.cgColor)
    context.fillEllipse(in: center)
  }
}

@MainActor
private func makeOverlayPanel(frame: CGRect, screen: NSScreen, contentView: NSView) -> NSPanel {
  let panel = NSPanel(
    contentRect: frame,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false,
    screen: screen
  )
  panel.setFrame(frame, display: false)
  panel.isOpaque = false
  panel.backgroundColor = .clear
  panel.hasShadow = false
  panel.ignoresMouseEvents = true
  panel.hidesOnDeactivate = false
  panel.level = .statusBar
  panel.collectionBehavior = [
    .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
  ]
  contentView.autoresizingMask = [.width, .height]
  panel.contentView = contentView
  panel.setAccessibilityElement(false)
  return panel
}
