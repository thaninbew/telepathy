import AppKit
import CoreGraphics
import Foundation

enum CalibrationMode: Equatable {
  case full
  case quick
}

@MainActor
final class CalibrationOverlayController {
  private struct Target {
    let appKitPoint: CGPoint
    let quartzPoint: CGPoint
    let screenFrame: CGRect
  }

  private struct Surface {
    let panel: CalibrationPanel
    let view: CalibrationOverlayView
  }

  var onCapture: ((CGPoint) -> CalibrationSample?)?
  var onComplete: (([CalibrationSample], CalibrationMode) -> Void)?
  var onCancel: (() -> Void)?
  var onFailure: ((String) -> Void)?

  private var surfaces: [Surface] = []
  private var sequenceTask: Task<Void, Never>?
  private var keyMonitor: Any?
  private(set) var isRunning = false

  var displayCount: Int { NSScreen.screens.count }

  func start(mode: CalibrationMode = .full) {
    guard !isRunning else { return }
    let targets = makeTargets(mode: mode)
    guard !targets.isEmpty else {
      onFailure?("No active displays are available for calibration.")
      return
    }

    isRunning = true
    rebuildSurfaces()
    installEscapeMonitor()
    NSApplication.shared.activate()
    surfaces.first?.panel.makeKeyAndOrderFront(nil)
    surfaces.dropFirst().forEach { $0.panel.orderFrontRegardless() }

    sequenceTask = Task { [weak self] in
      await self?.run(targets: targets, mode: mode)
    }
  }

  func cancel() {
    guard isRunning else { return }
    stop()
    onCancel?()
  }

  func stop() {
    guard isRunning else { return }
    sequenceTask?.cancel()
    finish()
  }

  private func run(targets: [Target], mode: CalibrationMode) async {
    var samples: [CalibrationSample] = []

    for (index, target) in targets.enumerated() {
      guard !Task.isCancelled else { return }
      let nextTarget = index + 1 < targets.count ? targets[index + 1] : nil
      show(target: target, nextTarget: nextTarget, index: index, total: targets.count, mode: mode)

      do {
        try await Task.sleep(for: mode == .full ? .milliseconds(2_800) : .milliseconds(600))
      } catch {
        return
      }

      let requiredCaptures = mode == .full ? 12 : 6
      var captures = 0
      var attempts = 0
      while captures < requiredCaptures, attempts < requiredCaptures * 6 {
        guard !Task.isCancelled else { return }
        attempts += 1
        if let sample = onCapture?(target.quartzPoint) {
          samples.append(sample)
          captures += 1
        }
        do {
          try await Task.sleep(for: .milliseconds(90))
        } catch {
          return
        }
      }

      guard captures == requiredCaptures else {
        finish()
        onFailure?(
          "Telepathy lost a clear view of your eyes. Adjust the camera or lighting and try again.")
        return
      }

      do {
        try await Task.sleep(for: .milliseconds(mode == .full ? 180 : 80))
      } catch {
        return
      }
    }

    finish()
    onComplete?(samples, mode)
  }

  private func makeTargets(mode: CalibrationMode) -> [Target] {
    NSScreen.screens
      .sorted {
        if $0.frame.minX != $1.frame.minX { return $0.frame.minX < $1.frame.minX }
        return $0.frame.minY < $1.frame.minY
      }
      .flatMap { screen in
        let points = CalibrationTargetPlanner.points(in: screen.frame)
        return (mode == .full ? points : Array(points.prefix(1))).map { appKitPoint in
          Target(
            appKitPoint: appKitPoint,
            quartzPoint: DesktopGeometry.quartzPoint(fromAppKit: appKitPoint),
            screenFrame: screen.frame
          )
        }
      }
  }

  private func rebuildSurfaces() {
    surfaces.forEach { $0.panel.orderOut(nil) }
    surfaces = NSScreen.screens.map { screen in
      let view = CalibrationOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
      let panel = CalibrationPanel(
        contentRect: screen.frame,
        styleMask: [.borderless],
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
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      panel.contentView = view
      panel.setAccessibilityElement(false)
      view.setAccessibilityElement(false)
      return Surface(panel: panel, view: view)
    }
  }

  private func show(
    target: Target,
    nextTarget: Target?,
    index: Int,
    total: Int,
    mode: CalibrationMode
  ) {
    for surface in surfaces {
      let isActive = surface.panel.frame.equalTo(target.screenFrame)
      surface.view.state = CalibrationOverlayState(
        targetPoint: isActive ? target.appKitPoint : nil,
        nextTargetPoint: isActive ? nextTarget?.appKitPoint : nil,
        progress: index + 1,
        total: total,
        isActive: isActive,
        mode: mode
      )
      surface.view.needsDisplay = true
    }
  }

  private func installEscapeMonitor() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 {
        Task { @MainActor [weak self] in self?.cancel() }
        return nil
      }
      return event
    }
  }

  private func finish() {
    guard isRunning else { return }
    isRunning = false
    sequenceTask = nil
    surfaces.forEach { $0.panel.orderOut(nil) }
    surfaces.removeAll()
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
  }
}

private final class CalibrationPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

private struct CalibrationOverlayState {
  var targetPoint: CGPoint?
  var nextTargetPoint: CGPoint?
  var progress = 0
  var total = 0
  var isActive = false
  var mode: CalibrationMode = .full
}

private final class CalibrationOverlayView: NSView {
  var state = CalibrationOverlayState()

  override var isFlipped: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let context = NSGraphicsContext.current?.cgContext else { return }

    context.setFillColor(OverlayStyle.calibrationBackdrop.cgColor)
    context.fill(bounds)

    guard state.isActive, let targetPoint = state.targetPoint else { return }
    let localPoint = CGPoint(
      x: targetPoint.x - (window?.frame.minX ?? 0),
      y: targetPoint.y - (window?.frame.minY ?? 0)
    )

    let halo = CGRect(
      x: localPoint.x - OverlayStyle.calibrationHaloRadius,
      y: localPoint.y - OverlayStyle.calibrationHaloRadius,
      width: OverlayStyle.calibrationHaloRadius * 2,
      height: OverlayStyle.calibrationHaloRadius * 2
    )
    context.setFillColor(OverlayStyle.accent.withAlphaComponent(0.12).cgColor)
    context.fillEllipse(in: halo)

    let target = CGRect(
      x: localPoint.x - OverlayStyle.calibrationTargetRadius,
      y: localPoint.y - OverlayStyle.calibrationTargetRadius,
      width: OverlayStyle.calibrationTargetRadius * 2,
      height: OverlayStyle.calibrationTargetRadius * 2
    )
    context.setStrokeColor(OverlayStyle.accent.cgColor)
    context.setLineWidth(2)
    context.strokeEllipse(in: target)

    let center = CGRect(x: localPoint.x - 2, y: localPoint.y - 2, width: 4, height: 4)
    context.setFillColor(OverlayStyle.accent.cgColor)
    context.fillEllipse(in: center)

    if let nextTargetPoint = state.nextTargetPoint {
      drawNextArrow(from: localPoint, toward: nextTargetPoint, context: context)
    }

    drawInstructions()
  }

  private func drawNextArrow(from start: CGPoint, toward nextGlobalPoint: CGPoint, context: CGContext) {
    let next = CGPoint(
      x: nextGlobalPoint.x - (window?.frame.minX ?? 0),
      y: nextGlobalPoint.y - (window?.frame.minY ?? 0)
    )
    let delta = CGPoint(x: next.x - start.x, y: next.y - start.y)
    let distance = max(hypot(delta.x, delta.y), 1)
    let unit = CGPoint(x: delta.x / distance, y: delta.y / distance)
    let tail = CGPoint(x: start.x + unit.x * 38, y: start.y + unit.y * 38)
    let tip = CGPoint(x: start.x + unit.x * 76, y: start.y + unit.y * 76)
    let perpendicular = CGPoint(x: -unit.y, y: unit.x)

    context.setStrokeColor(OverlayStyle.accent.withAlphaComponent(0.62).cgColor)
    context.setLineWidth(1.5)
    context.setLineCap(.round)
    context.move(to: tail)
    context.addLine(to: tip)
    context.move(to: tip)
    context.addLine(
      to: CGPoint(
        x: tip.x - unit.x * 10 + perpendicular.x * 6,
        y: tip.y - unit.y * 10 + perpendicular.y * 6
      )
    )
    context.move(to: tip)
    context.addLine(
      to: CGPoint(
        x: tip.x - unit.x * 10 - perpendicular.x * 6,
        y: tip.y - unit.y * 10 - perpendicular.y * 6
      )
    )
    context.strokePath()
  }

  private func drawInstructions() {
    let title = state.mode == .full ? "LOOK NATURALLY AT THE RING" : "QUICK RECENTER"
    let detail = "\(state.progress)/\(state.total)   •   ESC TO CANCEL"
    drawCentered(
      title,
      y: bounds.maxY - 72,
      font: .systemFont(ofSize: 13, weight: .semibold),
      color: OverlayStyle.text
    )
    drawCentered(
      detail,
      y: bounds.maxY - 96,
      font: .monospacedSystemFont(ofSize: 11, weight: .medium),
      color: OverlayStyle.telemetry
    )
  }

  private func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let value = NSAttributedString(
      string: text,
      attributes: [.font: font, .foregroundColor: color, .kern: 1.2]
    )
    let size = value.size()
    value.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: y))
  }
}
