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
    let displayID: CGDirectDisplayID
    let purpose: CalibrationTargetPurpose
  }

  private struct Surface {
    let panel: CalibrationPanel
    let view: CalibrationOverlayView
  }

  private enum Timing {
    static let fullTravelMilliseconds = 600
    static let quickTravelMilliseconds = 240
    static let crossDisplayCueMilliseconds = 420
    static let fullSettleMilliseconds = 500
    static let postureSettleMilliseconds = 750
    static let quickSettleMilliseconds = 350
    static let sampleIntervalMilliseconds = 90
    static let completedCueMilliseconds = 160
    static let postureCaptures = 44
    static let coverageCaptures = 6
    static let validationCaptures = 5
    static let quickCaptures = 6
  }

  var onCapture: ((CGPoint) -> CalibrationSample?)?
  var onComplete: (([CalibrationSample], CalibrationMode) -> Void)?
  var onCancel: (() -> Void)?
  var onFailure: ((String) -> Void)?

  private var surfaces: [Surface] = []
  private var sequenceTask: Task<Void, Never>?
  private var keyMonitor: Any?
  private(set) var isRunning = false
  var accentColor = OverlayStyle.accent {
    didSet {
      guard !accentColor.isEqual(oldValue) else { return }
      for surface in surfaces {
        surface.view.accentColor = accentColor
        surface.view.needsDisplay = true
      }
    }
  }

  var displayCount: Int { NSScreen.screens.count }

  func start(mode: CalibrationMode = .full) {
    guard !isRunning else { return }
    let targets = makeTrainingTargets(mode: mode)
    guard !targets.isEmpty else {
      onFailure?("No active displays are available for calibration.")
      return
    }

    isRunning = true
    rebuildSurfaces()
    installEscapeMonitor()
    NSApplication.shared.activate()
    surfaces.first?.panel.makeKeyAndOrderFront(nil)
    for surface in surfaces.dropFirst() {
      surface.panel.orderFrontRegardless()
    }

    sequenceTask = Task { [weak self] in
      await self?.run(trainingTargets: targets, mode: mode)
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

  private func run(trainingTargets: [Target], mode: CalibrationMode) async {
    let validationTargets = mode == .full ? makeValidationTargets() : []
    var samples: [CalibrationSample] = []
    var previousTarget: Target?

    for target in trainingTargets {
      guard !Task.isCancelled else { return }
      guard await move(from: previousTarget, to: target, mode: mode) else { return }

      showSettling(target: target)
      let settleMilliseconds: Int
      if mode == .quick {
        settleMilliseconds = Timing.quickSettleMilliseconds
      } else if target.purpose == .posture {
        settleMilliseconds = Timing.postureSettleMilliseconds
      } else {
        settleMilliseconds = Timing.fullSettleMilliseconds
      }
      guard await pause(milliseconds: settleMilliseconds) else { return }

      let requiredCaptures: Int
      switch (mode, target.purpose) {
      case (.quick, _): requiredCaptures = Timing.quickCaptures
      case (.full, .posture): requiredCaptures = Timing.postureCaptures
      case (.full, .coverage): requiredCaptures = Timing.coverageCaptures
      case (.full, .validation): requiredCaptures = Timing.validationCaptures
      }

      guard
        let captured = await collectSamples(
          at: target,
          requiredCaptures: requiredCaptures
        )
      else {
        guard !Task.isCancelled, isRunning else { return }
        failForLostTracking()
        return
      }
      samples.append(contentsOf: captured)
      previousTarget = target
    }

    var observations: [CalibrationValidationObservation] = []
    for target in validationTargets {
      guard !Task.isCancelled else { return }
      guard await move(from: previousTarget, to: target, mode: mode) else { return }

      showSettling(target: target)
      guard await pause(milliseconds: Timing.fullSettleMilliseconds) else { return }
      guard
        let captured = await collectSamples(
          at: target,
          requiredCaptures: Timing.validationCaptures
        )
      else {
        guard !Task.isCancelled, isRunning else { return }
        failForLostTracking()
        return
      }
      observations.append(
        contentsOf: captured.map {
          CalibrationValidationObservation(
            expectedDisplayID: target.displayID,
            features: $0.features
          )
        }
      )
      previousTarget = target
    }

    if mode == .full {
      let result = CalibrationValidator.evaluate(
        trainingSamples: samples,
        observations: observations,
        desktopBounds: DesktopGeometry.quartzBounds,
        displays: DesktopGeometry.activeDisplays
      )
      guard result.passed else {
        finish()
        onFailure?(
          "The new profile could not reliably distinguish every display during its final check. Keep your face visible, move only as far as you normally sit, and try Full Calibration again."
        )
        return
      }
    }

    finish()
    onComplete?(samples, mode)
  }

  private func collectSamples(
    at target: Target,
    requiredCaptures: Int
  ) async -> [CalibrationSample]? {
    var captured: [CalibrationSample] = []
    var attempts = 0
    var lastTimestamp: TimeInterval?
    let maximumAttempts = requiredCaptures + 60

    while captured.count < requiredCaptures, attempts < maximumAttempts {
      guard !Task.isCancelled else { return nil }
      attempts += 1

      if let sample = onCapture?(target.quartzPoint),
        lastTimestamp.map({ sample.features.timestamp > $0 + 0.01 }) ?? true
      {
        captured.append(sample)
        lastTimestamp = sample.features.timestamp
      }

      showCollecting(
        target: target,
        progress: CGFloat(captured.count) / CGFloat(requiredCaptures)
      )
      guard await pause(milliseconds: Timing.sampleIntervalMilliseconds) else { return nil }
    }

    guard captured.count == requiredCaptures else { return nil }
    guard await pause(milliseconds: Timing.completedCueMilliseconds) else { return nil }
    return captured
  }

  private func move(
    from previous: Target?,
    to target: Target,
    mode: CalibrationMode
  ) async -> Bool {
    guard let previous else {
      showMoving(
        target: target,
        displayedPoint: target.appKitPoint
      )
      return true
    }

    if !previous.screenFrame.equalTo(target.screenFrame) {
      showMoving(
        target: previous,
        displayedPoint: previous.appKitPoint,
        nextTarget: target
      )
      guard await pause(milliseconds: Timing.crossDisplayCueMilliseconds) else { return false }
      showMoving(
        target: target,
        displayedPoint: target.appKitPoint
      )
      return true
    }

    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      showMoving(
        target: target,
        displayedPoint: target.appKitPoint
      )
      return await pause(milliseconds: Timing.quickTravelMilliseconds)
    }

    let duration =
      mode == .full
      ? Timing.fullTravelMilliseconds
      : Timing.quickTravelMilliseconds
    let frameMilliseconds = 16
    let frameCount = max(duration / frameMilliseconds, 1)
    for frame in 1...frameCount {
      guard !Task.isCancelled else { return false }
      let linearProgress = CGFloat(frame) / CGFloat(frameCount)
      let easedProgress = linearProgress * linearProgress * (3 - 2 * linearProgress)
      let point = CGPoint(
        x: previous.appKitPoint.x
          + (target.appKitPoint.x - previous.appKitPoint.x) * easedProgress,
        y: previous.appKitPoint.y
          + (target.appKitPoint.y - previous.appKitPoint.y) * easedProgress
      )
      showMoving(
        target: target,
        displayedPoint: point
      )
      guard await pause(milliseconds: frameMilliseconds) else { return false }
    }
    return true
  }

  private func makeTrainingTargets(mode: CalibrationMode) -> [Target] {
    sortedScreens().flatMap { screen -> [Target] in
      guard let displayID = displayID(for: screen) else { return [] }
      let plans: [PlannedCalibrationTarget]
      if mode == .full {
        plans = CalibrationTargetPlanner.fullTrainingTargets(in: screen.frame)
      } else {
        plans = [
          PlannedCalibrationTarget(
            point: CGPoint(x: screen.frame.midX, y: screen.frame.midY),
            purpose: .posture
          )
        ]
      }
      return plans.map { target(from: $0, screen: screen, displayID: displayID) }
    }
  }

  private func makeValidationTargets() -> [Target] {
    sortedScreens().flatMap { screen -> [Target] in
      guard let displayID = displayID(for: screen) else { return [] }
      return CalibrationTargetPlanner.validationTargets(in: screen.frame).map {
        target(from: $0, screen: screen, displayID: displayID)
      }
    }
  }

  private func sortedScreens() -> [NSScreen] {
    NSScreen.screens.sorted {
      if $0.frame.minX != $1.frame.minX { return $0.frame.minX < $1.frame.minX }
      return $0.frame.minY < $1.frame.minY
    }
  }

  private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
  }

  private func target(
    from planned: PlannedCalibrationTarget,
    screen: NSScreen,
    displayID: CGDirectDisplayID
  ) -> Target {
    Target(
      appKitPoint: planned.point,
      quartzPoint: DesktopGeometry.quartzPoint(fromAppKit: planned.point),
      screenFrame: screen.frame,
      displayID: displayID,
      purpose: planned.purpose
    )
  }

  private func rebuildSurfaces() {
    for surface in surfaces {
      surface.panel.orderOut(nil)
    }
    surfaces = NSScreen.screens.map { screen in
      let view = CalibrationOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
      view.accentColor = accentColor
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

  private func showMoving(
    target: Target,
    displayedPoint: CGPoint,
    nextTarget: Target? = nil
  ) {
    show(
      target: target,
      displayedPoint: displayedPoint,
      nextTarget: nextTarget,
      ringProgress: 0
    )
  }

  private func showSettling(target: Target) {
    show(
      target: target,
      displayedPoint: target.appKitPoint,
      ringProgress: 0
    )
  }

  private func showCollecting(
    target: Target,
    progress: CGFloat
  ) {
    show(
      target: target,
      displayedPoint: target.appKitPoint,
      ringProgress: progress
    )
  }

  private func show(
    target: Target,
    displayedPoint: CGPoint,
    nextTarget: Target? = nil,
    ringProgress: CGFloat
  ) {
    for surface in surfaces {
      let isActive = surface.panel.frame.equalTo(target.screenFrame)
      surface.view.state = CalibrationOverlayState(
        targetPoint: isActive ? displayedPoint : nil,
        nextTargetPoint: isActive ? nextTarget?.appKitPoint : nil,
        ringProgress: min(max(ringProgress, 0), 1),
        isActive: isActive
      )
      surface.view.needsDisplay = true
    }
  }

  private func failForLostTracking() {
    finish()
    onFailure?(
      "Telepathy lost a clear, fresh camera view. Adjust the camera or lighting and try again."
    )
  }

  private func pause(milliseconds: Int) async -> Bool {
    do {
      try await Task.sleep(for: .milliseconds(milliseconds))
      return !Task.isCancelled
    } catch {
      return false
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
    for surface in surfaces {
      surface.panel.orderOut(nil)
    }
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
  var ringProgress: CGFloat = 0
  var isActive = false
}

private final class CalibrationOverlayView: NSView {
  var state = CalibrationOverlayState()
  var accentColor = OverlayStyle.accent

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
    context.setFillColor(accentColor.withAlphaComponent(0.12).cgColor)
    context.fillEllipse(in: halo)

    drawProgressRing(at: localPoint, context: context)

    let target = CGRect(
      x: localPoint.x - OverlayStyle.calibrationTargetRadius,
      y: localPoint.y - OverlayStyle.calibrationTargetRadius,
      width: OverlayStyle.calibrationTargetRadius * 2,
      height: OverlayStyle.calibrationTargetRadius * 2
    )
    context.setStrokeColor(accentColor.cgColor)
    context.setLineWidth(2)
    context.strokeEllipse(in: target)

    let center = CGRect(x: localPoint.x - 2, y: localPoint.y - 2, width: 4, height: 4)
    context.setFillColor(accentColor.cgColor)
    context.fillEllipse(in: center)

    if let nextTargetPoint = state.nextTargetPoint {
      drawNextArrow(from: localPoint, toward: nextTargetPoint, context: context)
    }

  }

  private func drawProgressRing(at point: CGPoint, context: CGContext) {
    let radius = OverlayStyle.calibrationProgressRadius
    context.setLineWidth(OverlayStyle.calibrationProgressLineWidth)
    context.setLineCap(.round)
    context.setStrokeColor(accentColor.withAlphaComponent(0.22).cgColor)
    context.strokeEllipse(
      in: CGRect(
        x: point.x - radius,
        y: point.y - radius,
        width: radius * 2,
        height: radius * 2
      )
    )

    guard state.ringProgress > 0 else { return }
    context.setStrokeColor(accentColor.withAlphaComponent(0.94).cgColor)
    context.addArc(
      center: point,
      radius: radius,
      startAngle: -.pi / 2,
      endAngle: -.pi / 2 + 2 * .pi * state.ringProgress,
      clockwise: false
    )
    context.strokePath()
  }

  private func drawNextArrow(
    from start: CGPoint, toward nextGlobalPoint: CGPoint, context: CGContext
  ) {
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

    context.setStrokeColor(accentColor.withAlphaComponent(0.62).cgColor)
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

}
