import AVFoundation
import AppKit
import CoreGraphics
import Foundation

@MainActor
final class TelepathyController: NSObject, NSMenuDelegate {
  private enum DefaultsKey {
    static let enabled = "telepathy.enabled"
    static let debugOverlay = "telepathy.debugOverlay"
    static let warpPointer = "telepathy.warpPointer"
    static let calibrationSamples = "telepathy.calibrationSamples.v1"
  }

  private let camera = CameraGazeTracker()
  private let mouseMonitor = MouseActivityMonitor()
  private let accessibility = AccessibilityWindowController()
  private let mapper = AdaptiveGazeMapper()
  private let overlay = DebugOverlayController()
  private var focusPolicy = FocusPolicy()

  private var latestFeatures: GazeFeatures?
  private var latestPrediction: GazePrediction?
  private var latestTarget: AccessibilityTarget?
  private var cameraState: CameraGazeTracker.State = .stopped
  private var statusItem: NSStatusItem?
  private var menu: NSMenu?

  private var enabled: Bool {
    didSet {
      UserDefaults.standard.set(enabled, forKey: DefaultsKey.enabled)
      if !enabled { focusPolicy.resetCandidate() }
      refreshMenu()
    }
  }

  private var debugOverlayEnabled: Bool {
    didSet {
      UserDefaults.standard.set(debugOverlayEnabled, forKey: DefaultsKey.debugOverlay)
      overlay.isVisible = debugOverlayEnabled
      refreshMenu()
    }
  }

  private var warpPointer: Bool {
    didSet {
      UserDefaults.standard.set(warpPointer, forKey: DefaultsKey.warpPointer)
      refreshMenu()
    }
  }

  override init() {
    let defaults = UserDefaults.standard
    enabled = defaults.object(forKey: DefaultsKey.enabled) as? Bool ?? true
    debugOverlayEnabled = defaults.object(forKey: DefaultsKey.debugOverlay) as? Bool ?? true
    warpPointer = defaults.object(forKey: DefaultsKey.warpPointer) as? Bool ?? true
    super.init()
    restoreCalibration()
  }

  func start() {
    configureStatusItem()
    configureCallbacks()
    overlay.isVisible = debugOverlayEnabled
    overlay.show()

    _ = accessibility.requestTrustPrompt()
    _ = mouseMonitor.start()
    camera.start()
    refreshOverlay()
    refreshMenu()
  }

  func stop() {
    camera.stop()
    mouseMonitor.stop()
  }

  private func configureCallbacks() {
    camera.onFeatures = { [weak self] features in
      self?.consume(features)
    }
    camera.onStateChange = { [weak self] state in
      self?.cameraState = state
      self?.refreshOverlay()
      self?.refreshMenu()
    }
    mouseMonitor.onClick = { [weak self] point, now in
      self?.learnFromClick(at: point, now: now)
    }
    mouseMonitor.onEmergencyToggle = { [weak self] in
      guard let self else { return }
      self.enabled.toggle()
      self.refreshOverlay()
    }
  }

  private func consume(_ features: GazeFeatures) {
    latestFeatures = features
    let bounds = DesktopGeometry.quartzBounds

    if accessibility.isTrusted, !mouseMonitor.isRunning {
      _ = mouseMonitor.start()
    }

    guard let rawPoint = mapper.predict(features: features, desktopBounds: bounds) else {
      latestPrediction = nil
      latestTarget = nil
      refreshOverlay()
      refreshMenu()
      return
    }

    let smoothedPoint: CGPoint
    if let previous = latestPrediction?.smoothedPoint {
      let newWeight: CGFloat = 0.72
      smoothedPoint = CGPoint(
        x: rawPoint.x * newWeight + previous.x * (1 - newWeight),
        y: rawPoint.y * newWeight + previous.y * (1 - newWeight)
      )
    } else {
      smoothedPoint = rawPoint
    }

    latestPrediction = GazePrediction(
      rawPoint: rawPoint,
      smoothedPoint: smoothedPoint,
      confidence: features.confidence,
      sampleCount: mapper.sampleCount
    )

    let target = accessibility.window(at: smoothedPoint)
    latestTarget = target?.metadata.processIdentifier == getpid() ? nil : target
    transferFocusIfNeeded(now: features.timestamp)
    refreshOverlay()
  }

  private func transferFocusIfNeeded(now: TimeInterval) {
    guard enabled,
      accessibility.isTrusted,
      let prediction = latestPrediction,
      let target = latestTarget
    else {
      focusPolicy.resetCandidate()
      return
    }

    let shouldTransfer = focusPolicy.shouldTransfer(
      to: target.metadata.identity,
      currentIdentity: accessibility.focusedWindowIdentity(),
      now: now,
      lastPhysicalMouseActivity: mouseMonitor.lastPhysicalMouseActivity
    )
    guard shouldTransfer else { return }

    if warpPointer {
      mouseMonitor.prepareForCursorWarp(now: now)
    }
    _ = accessibility.focus(
      target,
      warpPointerTo: warpPointer ? prediction.smoothedPoint : nil
    )
  }

  private func learnFromClick(at point: CGPoint, now: TimeInterval) {
    guard let features = latestFeatures,
      now - features.timestamp <= 0.25,
      features.confidence >= 0.35
    else {
      return
    }
    mapper.addSample(features: features, point: point, desktopBounds: DesktopGeometry.quartzBounds)
    persistCalibration()
    refreshOverlay()
    refreshMenu()
  }

  private func restoreCalibration() {
    guard let data = UserDefaults.standard.data(forKey: DefaultsKey.calibrationSamples),
      let samples = try? JSONDecoder().decode([CalibrationSample].self, from: data)
    else {
      return
    }
    mapper.restore(samples: samples)
  }

  private func persistCalibration() {
    guard let data = try? JSONEncoder().encode(mapper.samples) else { return }
    UserDefaults.standard.set(data, forKey: DefaultsKey.calibrationSamples)
  }

  private func refreshOverlay() {
    let status: String
    switch cameraState {
    case .stopped:
      status = "CAMERA STOPPED"
    case .requestingPermission:
      status = "CAMERA PERMISSION"
    case .denied:
      status = "CAMERA DENIED"
    case .unavailable(let message):
      status = "CAMERA ERROR  \(message)"
    case .running where !accessibility.isTrusted:
      status = "ACCESSIBILITY REQUIRED"
    case .running where !mapper.isReady:
      status =
        "LEARNING  \(mapper.sampleCount)/\(AdaptiveGazeMapper.minimumSampleCount)  CLICK WHAT YOU LOOK AT"
    case .running where !enabled:
      status = "PAUSED  ⌘⌥ESC"
    case .running:
      status = "TRACKING"
    }

    overlay.update(
      rawPoint: latestPrediction?.rawPoint,
      smoothedPoint: latestPrediction?.smoothedPoint,
      targetFrame: latestTarget?.metadata.frame,
      status: status,
      confidence: latestPrediction?.confidence
    )
  }

  private func configureStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = item.button {
      button.image = NSImage(systemSymbolName: "eye.circle", accessibilityDescription: "Telepathy")
      button.toolTip = "Telepathy"
    }
    let menu = NSMenu(title: "Telepathy")
    menu.delegate = self
    item.menu = menu
    statusItem = item
    self.menu = menu
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    refreshMenu()
  }

  private func refreshMenu() {
    guard let menu else { return }
    menu.removeAllItems()

    let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
    status.isEnabled = false
    menu.addItem(status)
    menu.addItem(.separator())

    let enabledItem = NSMenuItem(
      title: "Focus follows gaze", action: #selector(toggleEnabled), keyEquivalent: "")
    enabledItem.target = self
    enabledItem.state = enabled ? .on : .off
    menu.addItem(enabledItem)

    let debugItem = NSMenuItem(
      title: "Debug overlay", action: #selector(toggleDebugOverlay), keyEquivalent: "")
    debugItem.target = self
    debugItem.state = debugOverlayEnabled ? .on : .off
    menu.addItem(debugItem)

    let warpItem = NSMenuItem(
      title: "Warp pointer on transfer", action: #selector(toggleWarpPointer), keyEquivalent: "")
    warpItem.target = self
    warpItem.state = warpPointer ? .on : .off
    menu.addItem(warpItem)

    menu.addItem(.separator())

    if !accessibility.isTrusted {
      let permissionItem = NSMenuItem(
        title: "Request Accessibility access…", action: #selector(requestAccessibility),
        keyEquivalent: "")
      permissionItem.target = self
      menu.addItem(permissionItem)
    }

    let resetItem = NSMenuItem(
      title: "Reset learned calibration…", action: #selector(resetCalibration), keyEquivalent: "")
    resetItem.target = self
    resetItem.isEnabled = mapper.sampleCount > 0
    menu.addItem(resetItem)

    menu.addItem(.separator())
    let emergency = NSMenuItem(title: "Emergency pause: ⌘⌥Esc", action: nil, keyEquivalent: "")
    emergency.isEnabled = false
    menu.addItem(emergency)

    let quitItem = NSMenuItem(title: "Quit Telepathy", action: #selector(quit), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)
  }

  private var statusText: String {
    switch cameraState {
    case .stopped: "Camera stopped"
    case .requestingPermission: "Waiting for Camera permission"
    case .denied: "Camera permission denied"
    case .unavailable(let message): "Camera unavailable: \(message)"
    case .running where !accessibility.isTrusted: "Accessibility permission required"
    case .running where !mapper.isReady:
      "Learning gaze: \(mapper.sampleCount)/\(AdaptiveGazeMapper.minimumSampleCount) samples"
    case .running where !enabled: "Paused"
    case .running: "Tracking gaze"
    }
  }

  @objc private func toggleEnabled() {
    enabled.toggle()
    refreshOverlay()
  }

  @objc private func toggleDebugOverlay() {
    debugOverlayEnabled.toggle()
  }

  @objc private func toggleWarpPointer() {
    warpPointer.toggle()
  }

  @objc private func requestAccessibility() {
    _ = accessibility.requestTrustPrompt()
    refreshMenu()
    refreshOverlay()
  }

  @objc private func resetCalibration() {
    let alert = NSAlert()
    alert.messageText = "Reset gaze calibration?"
    alert.informativeText = "Telepathy will relearn from your next clicks."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Reset")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }

    mapper.reset()
    latestPrediction = nil
    latestTarget = nil
    UserDefaults.standard.removeObject(forKey: DefaultsKey.calibrationSamples)
    refreshOverlay()
    refreshMenu()
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }
}
