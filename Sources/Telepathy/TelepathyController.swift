import AVFoundation
import AppKit
import CoreGraphics
import Foundation

@MainActor
final class TelepathyController: NSObject, NSMenuDelegate {
  private enum DefaultsKey {
    static let enabled = "telepathy.enabled"
    static let debugOverlay = "telepathy.debugOverlay"
    static let screenFeedback = "telepathy.screenFeedback"
    static let warpPointer = "telepathy.warpPointer"
    static let activationMode = "telepathy.activationMode"
    static let shortcutKeyCode = "telepathy.shortcutKeyCode"
    static let shortcutDisplayName = "telepathy.shortcutDisplayName"
    static let switchDelay = "telepathy.switchDelay"
    static let autoReturnInterval = "telepathy.autoReturnInterval"
    static let accentTheme = "telepathy.accentTheme"
  }

  private let camera = CameraGazeTracker()
  private let mouseMonitor = MouseActivityMonitor()
  private let accessibility = AccessibilityWindowController()
  private let mapper = AdaptiveGazeMapper()
  private let displayClassifier = HeadDisplayClassifier()
  private let calibrationStore = CalibrationProfileStore()
  private let overlay = DebugOverlayController()
  private lazy var controlPanel = ControlPanelController()
  private lazy var calibrationOverlay = CalibrationOverlayController()
  private var switchPolicy = DisplaySwitchPolicy()
  private let feedbackPresentationPolicy = FeedbackPresentationPolicy()
  private var autoReturnPolicy = AutoReturnPolicy()

  private var latestFeatures: GazeFeatures?
  private var latestPrediction: GazePrediction?
  private var latestDisplayPrediction: DisplayPrediction?
  private var pendingConfirmation: ConfirmationSignal = .none
  private var pendingConfirmationDisplayID: CGDirectDisplayID?
  private var pendingConfirmationAt: TimeInterval = -.infinity
  private var recentWindows: [CGDirectDisplayID: AccessibilityTarget] = [:]
  private var recentPointerPositions: [CGDirectDisplayID: CGPoint] = [:]
  private var currentExternalDisplayID: CGDirectDisplayID?
  private var feedbackDisplayFrame: CGRect?
  private var feedbackPhase: DisplayFeedbackPhase?
  private var feedbackTask: Task<Void, Never>?
  private var autoReturnTask: Task<Void, Never>?
  private var currentLayoutFingerprint = DesktopGeometry.layoutFingerprint
  private var displayObserver: NSObjectProtocol?
  private var isCalibrating = false
  private var cameraState: CameraGazeTracker.State = .stopped
  private var statusItem: NSStatusItem?
  private var menu: NSMenu?

  private var trackingReady: Bool {
    mapper.isReady && (DesktopGeometry.activeDisplays.count < 2 || displayClassifier.isReady)
  }

  private var enabled: Bool {
    didSet {
      UserDefaults.standard.set(enabled, forKey: DefaultsKey.enabled)
      if !enabled {
        switchPolicy.resetCandidate()
        cancelAutoReturn()
        clearFeedback()
      }
      refreshOverlay()
      refreshMenu()
      refreshControlPanel()
    }
  }

  private var debugOverlayEnabled: Bool {
    didSet {
      UserDefaults.standard.set(debugOverlayEnabled, forKey: DefaultsKey.debugOverlay)
      refreshOverlay()
      refreshMenu()
      refreshControlPanel()
    }
  }

  private var screenFeedbackEnabled: Bool {
    didSet {
      UserDefaults.standard.set(screenFeedbackEnabled, forKey: DefaultsKey.screenFeedback)
      if !screenFeedbackEnabled { clearFeedback() }
      refreshOverlay()
      refreshMenu()
      refreshControlPanel()
    }
  }

  private var warpPointer: Bool {
    didSet {
      UserDefaults.standard.set(warpPointer, forKey: DefaultsKey.warpPointer)
      refreshMenu()
    }
  }

  private var activationMode: ActivationMode {
    didSet {
      UserDefaults.standard.set(activationMode.rawValue, forKey: DefaultsKey.activationMode)
      switchPolicy.resetCandidate()
      clearPendingConfirmation()
      cancelAutoReturn()
      clearFeedback()
      refreshMenu()
      refreshControlPanel()
    }
  }

  private var shortcut: ShortcutBinding {
    didSet {
      UserDefaults.standard.set(shortcut.keyCode, forKey: DefaultsKey.shortcutKeyCode)
      UserDefaults.standard.set(shortcut.displayName, forKey: DefaultsKey.shortcutDisplayName)
      mouseMonitor.shortcut = shortcut
      clearPendingConfirmation()
      refreshMenu()
      refreshControlPanel()
    }
  }

  private var switchDelay: TimeInterval {
    didSet {
      UserDefaults.standard.set(switchDelay, forKey: DefaultsKey.switchDelay)
      switchPolicy.stabilityInterval = switchDelay
      switchPolicy.resetCandidate()
      clearPendingConfirmation()
      cancelAutoReturn()
      clearFeedback()
      refreshMenu()
      refreshControlPanel()
    }
  }

  private var autoReturnInterval: TimeInterval {
    didSet {
      UserDefaults.standard.set(autoReturnInterval, forKey: DefaultsKey.autoReturnInterval)
      cancelAutoReturn()
      refreshMenu()
      refreshControlPanel()
    }
  }

  private var accentTheme: AccentTheme {
    didSet {
      if let data = try? JSONEncoder().encode(accentTheme) {
        UserDefaults.standard.set(data, forKey: DefaultsKey.accentTheme)
      }
      refreshOverlay()
      refreshMenu()
      refreshControlPanel()
    }
  }

  private var resolvedAccent: AccentColor {
    accentTheme.resolved()
  }

  override init() {
    let defaults = UserDefaults.standard
    enabled = defaults.object(forKey: DefaultsKey.enabled) as? Bool ?? true
    debugOverlayEnabled = defaults.object(forKey: DefaultsKey.debugOverlay) as? Bool ?? false
    screenFeedbackEnabled = defaults.object(forKey: DefaultsKey.screenFeedback) as? Bool ?? true
    warpPointer = defaults.object(forKey: DefaultsKey.warpPointer) as? Bool ?? true
    activationMode = ActivationMode(
      rawValue: defaults.string(forKey: DefaultsKey.activationMode) ?? "") ?? .automatic
    var migratedLegacyShortcut = false
    if let keyCode = defaults.object(forKey: DefaultsKey.shortcutKeyCode) as? NSNumber,
      let displayName = defaults.string(forKey: DefaultsKey.shortcutDisplayName),
      !displayName.isEmpty
    {
      let stored = ShortcutBinding(keyCode: keyCode.int64Value, displayName: displayName)
      if stored == .legacyRightShiftDefault {
        shortcut = .defaultValue
        migratedLegacyShortcut = true
      } else {
        shortcut = stored
      }
    } else {
      shortcut = .defaultValue
    }
    switchDelay =
      (defaults.object(forKey: DefaultsKey.switchDelay) as? NSNumber)?.doubleValue ?? 0.09
    autoReturnInterval =
      (defaults.object(forKey: DefaultsKey.autoReturnInterval) as? NSNumber)?.doubleValue ?? 0
    accentTheme = defaults.data(forKey: DefaultsKey.accentTheme).flatMap {
      try? JSONDecoder().decode(AccentTheme.self, from: $0)
    } ?? .defaultValue
    super.init()
    if migratedLegacyShortcut {
      defaults.set(shortcut.keyCode, forKey: DefaultsKey.shortcutKeyCode)
      defaults.set(shortcut.displayName, forKey: DefaultsKey.shortcutDisplayName)
    }
    switchPolicy.stabilityInterval = switchDelay
    mouseMonitor.shortcut = shortcut
    restoreCalibration()
  }

  func start() {
    configureStatusItem()
    configureControlPanel()
    configureCalibration()
    configureCallbacks()
    configureDisplayObserver()

    overlay.accentColor = resolvedAccent.nsColor
    calibrationOverlay.accentColor = resolvedAccent.nsColor

    if accessibility.isTrusted {
      _ = mouseMonitor.start()
    }
    camera.start()
    refreshOverlay()
    refreshMenu()
    refreshControlPanel()
    if !accessibility.isTrusted || !mapper.isReady {
      controlPanel.present()
    }
  }

  func stop() {
    feedbackTask?.cancel()
    autoReturnTask?.cancel()
    calibrationOverlay.stop()
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
      self?.refreshControlPanel()
    }
    mouseMonitor.onClick = { [weak self] point, now in
      self?.learnFromClick(at: point, now: now)
    }
    mouseMonitor.onPointerActivity = { [weak self] point, _ in
      self?.handlePhysicalPointerActivity(at: point)
    }
    mouseMonitor.onConfirmation = { [weak self] signal, now in
      guard let self else { return }
      self.pendingConfirmation = signal
      self.pendingConfirmationAt = now
      self.pendingConfirmationDisplayID = self.latestDisplayPrediction?.displayID
    }
    mouseMonitor.onEmergencyToggle = { [weak self] in
      guard let self else { return }
      self.enabled.toggle()
    }
  }

  private func consume(_ features: GazeFeatures) {
    latestFeatures = features
    let bounds = DesktopGeometry.quartzBounds

    if accessibility.isTrusted, !mouseMonitor.isRunning {
      _ = mouseMonitor.start()
    }

    guard !isCalibrating else { return }

    updateExperimentalGazePrediction(features: features, bounds: bounds)
    rememberFocusedContext()

    latestDisplayPrediction = displayClassifier.predict(features: features)
    transferDisplayIfNeeded(now: features.timestamp)
    refreshOverlay()
    refreshControlPanel()
  }

  private func updateExperimentalGazePrediction(features: GazeFeatures, bounds: CGRect) {
    guard let rawPoint = mapper.predict(features: features, desktopBounds: bounds) else {
      latestPrediction = nil
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
  }

  private func transferDisplayIfNeeded(now: TimeInterval) {
    guard enabled, !isCalibrating, accessibility.isTrusted,
      let prediction = latestDisplayPrediction,
      prediction.confidence >= 0.52
    else {
      switchPolicy.resetCandidate()
      clearPendingConfirmation()
      updateFeedback(for: DisplaySwitchDecision(targetDisplayID: nil, phase: .idle), now: now)
      return
    }

    if autoReturnPolicy.shouldSuppress(prediction.displayID) {
      switchPolicy.resetCandidate()
      clearPendingConfirmation()
      updateFeedback(for: DisplaySwitchDecision(targetDisplayID: nil, phase: .idle), now: now)
      return
    }

    let signal = confirmationSignal(for: prediction.displayID, now: now)
    let decision = switchPolicy.evaluate(
      targetDisplayID: prediction.displayID,
      currentDisplayID: currentExternalDisplayID,
      mode: activationMode,
      now: now,
      lastPhysicalMouseActivity: mouseMonitor.lastPhysicalMouseActivity,
      signal: signal
    )
    updateFeedback(for: decision, now: now)
    guard decision.phase == .commit, let displayID = decision.targetDisplayID else { return }
    clearPendingConfirmation()
    transfer(to: displayID, now: now)
  }

  private func confirmationSignal(
    for displayID: CGDirectDisplayID,
    now: TimeInterval
  ) -> ConfirmationSignal {
    if activationMode == .keyboard, mouseMonitor.isShortcutPressed {
      return .keyboard
    }

    guard pendingConfirmation != .none else { return .none }
    guard now - pendingConfirmationAt <= ConfirmationTiming.latchInterval(switchDelay: switchDelay)
    else {
      clearPendingConfirmation()
      return .none
    }
    guard pendingConfirmationDisplayID == nil || pendingConfirmationDisplayID == displayID else {
      return .none
    }
    return pendingConfirmation
  }

  private func clearPendingConfirmation() {
    pendingConfirmation = .none
    pendingConfirmationDisplayID = nil
    pendingConfirmationAt = -.infinity
  }

  private func rememberFocusedContext() {
    guard let target = accessibility.focusedWindow(),
      target.metadata.processIdentifier != getpid(),
      let display = DesktopGeometry.display(owning: target.metadata.frame)
    else { return }
    recentWindows[display.id] = target
    currentExternalDisplayID = display.id
  }

  private func rememberPointer(at point: CGPoint) {
    guard let display = DesktopGeometry.display(containing: point) else { return }
    recentPointerPositions[display.id] = DesktopGeometry.clamp(point, to: display.visibleBounds)
  }

  private func handlePhysicalPointerActivity(at point: CGPoint) {
    rememberPointer(at: point)
    guard let displayID = DesktopGeometry.display(containing: point)?.id,
      autoReturnPolicy.pointerActivity(on: displayID)
    else { return }
    autoReturnTask?.cancel()
    autoReturnTask = nil
  }

  @discardableResult
  private func transfer(
    to displayID: CGDirectDisplayID,
    now: TimeInterval,
    scheduleAutoReturn: Bool = true
  ) -> Bool {
    guard let display = DesktopGeometry.activeDisplays.first(where: { $0.id == displayID }) else {
      return false
    }
    let originDisplayID = currentExternalDisplayID
    if let cursor = CGEvent(source: nil)?.location { rememberPointer(at: cursor) }

    let remembered = recentWindows[displayID].flatMap {
      accessibility.eligibleTarget(
        from: $0,
        on: display,
        excludingProcessIdentifier: getpid()
      )
    }
    let target = remembered ?? accessibility.frontmostEligibleTarget(
      on: display,
      excludingProcessIdentifier: getpid()
    )
    let pointer = recentPointerPositions[displayID].map {
      DesktopGeometry.clamp($0, to: display.visibleBounds)
    } ?? CGPoint(x: display.visibleBounds.midX, y: display.visibleBounds.midY)

    if warpPointer { mouseMonitor.prepareForCursorWarp(now: now) }
    var succeeded = false
    if let target {
      let focused = accessibility.focus(target, warpPointerTo: warpPointer ? pointer : nil)
      if focused {
        recentWindows[displayID] = target
        currentExternalDisplayID = displayID
        showConfirmedFeedback(on: display)
        succeeded = true
      }
    } else if warpPointer {
      accessibility.warpPointer(to: pointer)
      currentExternalDisplayID = displayID
      showConfirmedFeedback(on: display)
      succeeded = true
    }
    guard succeeded else { return false }
    updateAutoReturn(
      from: originDisplayID,
      to: displayID,
      enabled: scheduleAutoReturn && autoReturnInterval > 0
    )
    return true
  }

  private func updateAutoReturn(
    from originDisplayID: CGDirectDisplayID?,
    to targetDisplayID: CGDirectDisplayID,
    enabled: Bool
  ) {
    autoReturnTask?.cancel()
    autoReturnTask = nil
    guard
      let plan = autoReturnPolicy.switched(
        from: originDisplayID,
        to: targetDisplayID,
        enabled: enabled
      )
    else { return }

    let delay = autoReturnInterval
    autoReturnTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled, let self,
        let returnDisplayID = self.autoReturnPolicy.fire(plan)
      else { return }
      self.autoReturnTask = nil
      let returned = self.transfer(
        to: returnDisplayID,
        now: ProcessInfo.processInfo.systemUptime,
        scheduleAutoReturn: false
      )
      if !returned { self.autoReturnPolicy.returnFailed() }
    }
  }

  private func cancelAutoReturn() {
    autoReturnTask?.cancel()
    autoReturnTask = nil
    autoReturnPolicy.cancel()
  }

  private func learnFromClick(at point: CGPoint, now: TimeInterval) {
    guard !isCalibrating,
      let features = latestFeatures,
      now - features.timestamp <= 0.25,
      features.confidence >= 0.35
    else {
      return
    }
    mapper.addSample(features: features, point: point, desktopBounds: DesktopGeometry.quartzBounds)
    refitDisplayClassifier()
    persistCalibration()
    refreshOverlay()
    refreshMenu()
    refreshControlPanel()
  }

  private func restoreCalibration() {
    mapper.reset()
    displayClassifier.reset()
    guard let samples = calibrationStore.load(layout: currentLayoutFingerprint) else { return }
    mapper.restore(samples: samples)
    refitDisplayClassifier()
  }

  private func refitDisplayClassifier() {
    displayClassifier.fit(
      samples: mapper.samples,
      desktopBounds: DesktopGeometry.quartzBounds,
      displays: DesktopGeometry.activeDisplays
    )
  }

  private func persistCalibration() {
    calibrationStore.save(samples: mapper.samples, layout: currentLayoutFingerprint)
  }

  private func refreshOverlay() {
    overlay.accentColor = resolvedAccent.nsColor
    let gazePoint = debugOverlayEnabled ? latestPrediction?.smoothedPoint : nil
    let phase = screenFeedbackEnabled ? feedbackPhase : nil
    overlay.isVisible = enabled && !isCalibrating && (gazePoint != nil || phase != nil)
    overlay.update(
      gazePoint: gazePoint,
      displayFrame: phase == nil ? nil : feedbackDisplayFrame,
      feedbackPhase: phase
    )
  }

  private func updateFeedback(for decision: DisplaySwitchDecision, now: TimeInterval) {
    guard feedbackTask == nil else { return }
    guard screenFeedbackEnabled,
      let displayID = decision.targetDisplayID,
      let display = DesktopGeometry.activeDisplays.first(where: { $0.id == displayID })
    else {
      if feedbackTask == nil {
        feedbackDisplayFrame = nil
        feedbackPhase = nil
      }
      return
    }

    let phase = feedbackPresentationPolicy.phase(
      for: decision,
      candidateSince: switchPolicy.candidateSince,
      stabilityInterval: switchDelay,
      now: now
    )
    feedbackDisplayFrame = phase == nil ? nil : display.bounds
    feedbackPhase = phase
  }

  private func showConfirmedFeedback(on display: ActiveDisplay) {
    guard screenFeedbackEnabled else { return }
    feedbackTask?.cancel()
    feedbackDisplayFrame = display.bounds
    feedbackPhase = .confirmed(progress: 0)
    refreshOverlay()
    feedbackTask = Task { [weak self] in
      if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        self?.feedbackPhase = .confirmed(progress: 0.28)
        self?.refreshOverlay()
        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled else { return }
        self?.finishFeedbackAnimation()
        return
      }

      let steps = 18
      for step in 1...steps {
        try? await Task.sleep(for: .milliseconds(30))
        guard !Task.isCancelled else { return }
        self?.feedbackPhase = .confirmed(progress: Double(step) / Double(steps))
        self?.refreshOverlay()
      }
      self?.finishFeedbackAnimation()
    }
  }

  private func finishFeedbackAnimation() {
    feedbackTask = nil
    feedbackDisplayFrame = nil
    feedbackPhase = nil
    refreshOverlay()
  }

  private func clearFeedback() {
    feedbackTask?.cancel()
    feedbackTask = nil
    feedbackDisplayFrame = nil
    feedbackPhase = nil
  }

  private func configureControlPanel() {
    controlPanel.onEnabledChanged = { [weak self] isEnabled in
      guard let self, self.enabled != isEnabled else { return }
      self.enabled = isEnabled
    }
    controlPanel.onGazeIndicatorChanged = { [weak self] isEnabled in
      guard let self, self.debugOverlayEnabled != isEnabled else { return }
      self.debugOverlayEnabled = isEnabled
    }
    controlPanel.onScreenFeedbackChanged = { [weak self] isEnabled in
      guard let self, self.screenFeedbackEnabled != isEnabled else { return }
      self.screenFeedbackEnabled = isEnabled
    }
    controlPanel.onActivationModeChanged = { [weak self] mode in
      guard let self, self.activationMode != mode else { return }
      self.activationMode = mode
    }
    controlPanel.onShortcutChanged = { [weak self] shortcut in
      guard let self, self.shortcut != shortcut else { return }
      self.shortcut = shortcut
    }
    controlPanel.onSwitchDelayChanged = { [weak self] delay in
      guard let self, abs(self.switchDelay - delay) > 0.001 else { return }
      self.switchDelay = delay
    }
    controlPanel.onAutoReturnChanged = { [weak self] interval in
      guard let self, abs(self.autoReturnInterval - interval) > 0.001 else { return }
      self.autoReturnInterval = interval
    }
    controlPanel.onAccentSourceChanged = { [weak self] source in
      guard let self, self.accentTheme.source != source else { return }
      self.accentTheme.source = source
    }
    controlPanel.onCustomAccentChanged = { [weak self] color in
      guard let self, self.accentTheme.customColor != color else { return }
      self.accentTheme.customColor = color
    }
    controlPanel.onRequestAccessibility = { [weak self] in
      self?.requestAccessibility()
    }
    controlPanel.onCalibrate = { [weak self] in
      self?.beginCalibration()
    }
    controlPanel.onQuickRecenter = { [weak self] in
      self?.beginQuickRecenter()
    }
  }

  private func configureCalibration() {
    calibrationOverlay.onCapture = { [weak self] point in
      self?.calibrationSample(at: point)
    }
    calibrationOverlay.onComplete = { [weak self] samples, mode in
      self?.completeCalibration(with: samples, mode: mode)
    }
    calibrationOverlay.onCancel = { [weak self] in
      self?.finishCalibration()
    }
    calibrationOverlay.onFailure = { [weak self] message in
      self?.failCalibration(message: message)
    }
  }

  private func configureDisplayObserver() {
    displayObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.handleDisplayChange()
      }
    }
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

    if let button = statusItem?.button {
      button.image = NSImage(
        systemSymbolName: enabled ? "eye.circle.fill" : "eye.slash.circle",
        accessibilityDescription: enabled ? "Telepathy on" : "Telepathy off"
      )
      button.toolTip = enabled ? "Telepathy is on" : "Telepathy is off"
    }

    let openItem = NSMenuItem(
      title: "Open Telepathy…", action: #selector(openControlPanel), keyEquivalent: ""
    )
    openItem.target = self
    menu.addItem(openItem)
    menu.addItem(.separator())

    let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
    status.isEnabled = false
    menu.addItem(status)
    menu.addItem(.separator())

    let enabledItem = NSMenuItem(
      title: enabled ? "Turn Telepathy Off" : "Turn Telepathy On",
      action: #selector(toggleEnabled),
      keyEquivalent: ""
    )
    enabledItem.target = self
    menu.addItem(enabledItem)

    let feedbackItem = NSMenuItem(
      title: "Show screen bloom", action: #selector(toggleScreenFeedback), keyEquivalent: "")
    feedbackItem.target = self
    feedbackItem.state = screenFeedbackEnabled ? .on : .off
    menu.addItem(feedbackItem)

    let debugItem = NSMenuItem(
      title: "Show experimental gaze indicator", action: #selector(toggleDebugOverlay),
      keyEquivalent: "")
    debugItem.target = self
    debugItem.state = debugOverlayEnabled ? .on : .off
    menu.addItem(debugItem)

    let activationItem = NSMenuItem(title: "Activation", action: nil, keyEquivalent: "")
    let activationMenu = NSMenu(title: "Activation")
    for mode in ActivationMode.allCases {
      let item = NSMenuItem(
        title: mode.title(shortcutName: shortcut.displayName),
        action: #selector(selectActivationMode(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = mode.rawValue
      item.state = activationMode == mode ? .on : .off
      activationMenu.addItem(item)
    }
    activationMenu.addItem(.separator())
    let configureShortcut = NSMenuItem(
      title: "Configure shortcut…",
      action: #selector(openControlPanel),
      keyEquivalent: ""
    )
    configureShortcut.target = self
    activationMenu.addItem(configureShortcut)
    activationItem.submenu = activationMenu
    menu.addItem(activationItem)

    let warpItem = NSMenuItem(
      title: "Warp pointer on transfer", action: #selector(toggleWarpPointer), keyEquivalent: "")
    warpItem.target = self
    warpItem.state = warpPointer ? .on : .off
    menu.addItem(warpItem)

    menu.addItem(.separator())

    let calibrationItem = NSMenuItem(
      title: "Full Calibration…",
      action: #selector(beginCalibration),
      keyEquivalent: ""
    )
    calibrationItem.target = self
    calibrationItem.isEnabled = cameraState == .running && !isCalibrating
    menu.addItem(calibrationItem)

    let quickItem = NSMenuItem(
      title: "Quick Recenter…",
      action: #selector(beginQuickRecenter),
      keyEquivalent: ""
    )
    quickItem.target = self
    quickItem.isEnabled = trackingReady && cameraState == .running && !isCalibrating
    menu.addItem(quickItem)

    if !accessibility.isTrusted {
      let permissionItem = NSMenuItem(
        title: "Request Accessibility access…", action: #selector(requestAccessibility),
        keyEquivalent: "")
      permissionItem.target = self
      menu.addItem(permissionItem)
    }

    let resetItem = NSMenuItem(
      title: "Reset current calibration…", action: #selector(resetCalibration), keyEquivalent: "")
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

  private func refreshControlPanel() {
    let calibrationTitle = "Full Calibration…"
    let calibrationEnabled = cameraState == .running && !isCalibrating
    var state: ControlPanelState
    switch cameraState {
    case .stopped:
      state = ControlPanelState(
        enabled: enabled,
        status: "Camera stopped",
        detail: "Quit and reopen Telepathy to restart camera tracking.",
        gazeIndicatorEnabled: debugOverlayEnabled,
        calibrationButtonTitle: calibrationTitle,
        calibrationEnabled: calibrationEnabled,
        accessibilityReady: accessibility.isTrusted
      )
    case .requestingPermission:
      state = ControlPanelState(
        enabled: enabled,
        status: "Waiting for Camera access",
        detail: "Allow Camera access in the macOS prompt to begin local tracking.",
        gazeIndicatorEnabled: debugOverlayEnabled,
        calibrationButtonTitle: calibrationTitle,
        calibrationEnabled: calibrationEnabled,
        accessibilityReady: accessibility.isTrusted
      )
    case .denied:
      state = ControlPanelState(
        enabled: enabled,
        status: "Camera access needed",
        detail: "Enable Telepathy in System Settings > Privacy & Security > Camera.",
        gazeIndicatorEnabled: debugOverlayEnabled,
        calibrationButtonTitle: calibrationTitle,
        calibrationEnabled: calibrationEnabled,
        accessibilityReady: accessibility.isTrusted
      )
    case .unavailable(let message):
      state = ControlPanelState(
        enabled: enabled,
        status: "Camera unavailable",
        detail: message,
        gazeIndicatorEnabled: debugOverlayEnabled,
        calibrationButtonTitle: calibrationTitle,
        calibrationEnabled: calibrationEnabled,
        accessibilityReady: accessibility.isTrusted
      )
    case .running where isCalibrating:
      state = ControlPanelState(
        enabled: enabled,
        status: "Calibrating",
        detail:
          "Follow the colored target across \(calibrationOverlay.displayCount) active displays. Press Esc to cancel.",
        gazeIndicatorEnabled: debugOverlayEnabled,
        calibrationButtonTitle: "Calibrating…",
        calibrationEnabled: false,
        accessibilityReady: accessibility.isTrusted
      )
    case .running where !enabled:
      state = ControlPanelState(
        enabled: false,
        status: "Off",
        detail:
          "Camera estimation may continue locally, but focus and pointer movement are paused.",
        gazeIndicatorEnabled: debugOverlayEnabled,
        calibrationButtonTitle: calibrationTitle,
        calibrationEnabled: calibrationEnabled,
        accessibilityReady: accessibility.isTrusted
      )
    case .running where !accessibility.isTrusted:
      state = ControlPanelState(
        enabled: enabled,
        status: "Accessibility access needed",
        detail:
          "Grant access once to the installed Telepathy app so it can focus windows and move the pointer.",
        gazeIndicatorEnabled: debugOverlayEnabled,
        calibrationButtonTitle: calibrationTitle,
        calibrationEnabled: calibrationEnabled,
        accessibilityReady: false
      )
    case .running where !trackingReady:
      state = ControlPanelState(
        enabled: enabled,
        status: "Calibration needed",
        detail:
          "Run Full Calibration for the current screens. Clicks will keep refining screen selection.",
        gazeIndicatorEnabled: debugOverlayEnabled,
        calibrationButtonTitle: calibrationTitle,
        calibrationEnabled: calibrationEnabled,
        accessibilityReady: true
      )
    case .running:
      state = ControlPanelState(
        enabled: enabled,
        status: "Tracking",
        detail:
          "Turn your head toward another display. Telepathy restores that display context only.",
        gazeIndicatorEnabled: debugOverlayEnabled,
        calibrationButtonTitle: calibrationTitle,
        calibrationEnabled: calibrationEnabled,
        accessibilityReady: true
      )
    }
    state.screenFeedbackEnabled = screenFeedbackEnabled
    state.activationMode = activationMode
    state.shortcut = shortcut
    state.switchDelay = switchDelay
    state.autoReturnInterval = autoReturnInterval
    state.accentTheme = accentTheme
    state.resolvedAccent = resolvedAccent
    state.quickRecenterEnabled = trackingReady && calibrationEnabled
    controlPanel.update(state)
  }

  private var statusText: String {
    switch cameraState {
    case .stopped: "Camera stopped"
    case .requestingPermission: "Waiting for Camera permission"
    case .denied: "Camera permission denied"
    case .unavailable(let message): "Camera unavailable: \(message)"
    case .running where isCalibrating: "Calibrating gaze"
    case .running where !accessibility.isTrusted: "Accessibility permission required"
    case .running where !trackingReady:
      "Calibration needed for this display layout"
    case .running where !enabled: "Paused"
    case .running: "Tracking display attention"
    }
  }

  private func calibrationSample(at point: CGPoint) -> CalibrationSample? {
    guard let features = latestFeatures,
      ProcessInfo.processInfo.systemUptime - features.timestamp <= 0.3,
      features.confidence >= 0.35
    else {
      return nil
    }
    return AdaptiveGazeMapper.makeSample(
      features: features,
      point: point,
      desktopBounds: DesktopGeometry.quartzBounds
    )
  }

  private func completeCalibration(with samples: [CalibrationSample], mode: CalibrationMode) {
    let proposedSamples = mode == .quick ? mapper.samples + samples : samples
    let candidate = AdaptiveGazeMapper()
    candidate.restore(samples: proposedSamples)
    guard candidate.isReady else {
      failCalibration(
        message:
          "The samples did not produce a reliable desktop map. Keep your face visible and try again."
      )
      return
    }

    mapper.restore(samples: proposedSamples)
    refitDisplayClassifier()
    persistCalibration()
    finishCalibration()
  }

  private func finishCalibration() {
    isCalibrating = false
    latestPrediction = nil
    latestDisplayPrediction = nil
    switchPolicy.resetCandidate()
    clearFeedback()
    refreshOverlay()
    refreshMenu()
    refreshControlPanel()
    controlPanel.present()
  }

  private func failCalibration(message: String) {
    finishCalibration()
    let alert = NSAlert()
    alert.messageText = "Calibration did not finish"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private func handleDisplayChange() {
    let fingerprint = DesktopGeometry.layoutFingerprint
    guard fingerprint != currentLayoutFingerprint else { return }

    if calibrationOverlay.isRunning {
      calibrationOverlay.cancel()
    }
    currentLayoutFingerprint = fingerprint
    restoreCalibration()
    latestPrediction = nil
    latestDisplayPrediction = nil
    recentWindows.removeAll()
    recentPointerPositions.removeAll()
    currentExternalDisplayID = nil
    switchPolicy.resetCandidate()
    cancelAutoReturn()
    clearFeedback()
    refreshOverlay()
    refreshMenu()
    refreshControlPanel()
    if !mapper.isReady {
      controlPanel.present()
    }
  }

  @objc private func toggleEnabled() {
    enabled.toggle()
  }

  @objc private func toggleDebugOverlay() {
    debugOverlayEnabled.toggle()
  }

  @objc private func toggleScreenFeedback() {
    screenFeedbackEnabled.toggle()
  }

  @objc private func toggleWarpPointer() {
    warpPointer.toggle()
  }

  @objc private func selectActivationMode(_ sender: NSMenuItem) {
    guard let rawValue = sender.representedObject as? String,
      let mode = ActivationMode(rawValue: rawValue)
    else { return }
    activationMode = mode
  }

  @objc private func beginCalibration() {
    startCalibration(mode: .full)
  }

  @objc private func beginQuickRecenter() {
    startCalibration(mode: .quick)
  }

  private func startCalibration(mode: CalibrationMode) {
    guard cameraState == .running, !isCalibrating else { return }
    guard mode == .full || trackingReady else { return }

    let displays = calibrationOverlay.displayCount
    let alert = NSAlert()
    if mode == .full {
      alert.messageText = trackingReady ? "Run Full Calibration again?" : "Run Full Calibration?"
      alert.informativeText =
        "Follow the colored target across \(displays) active \(displays == 1 ? "display" : "displays"). During Posture Range, move naturally in your chair while keeping the ring in view. Telepathy then learns screen coverage and checks unseen positions before saving. The deliberate pass takes about 45 seconds with two displays, and your current profile stays saved if you cancel or the final check fails."
    } else {
      alert.messageText = "Quick Recenter Telepathy?"
      alert.informativeText =
        "Look at the center of each active display. This takes a few seconds and adjusts the saved profile for your current posture without replacing Full Calibration."
    }
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Start")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }

    isCalibrating = true
    switchPolicy.resetCandidate()
    cancelAutoReturn()
    clearFeedback()
    controlPanel.dismiss()
    calibrationOverlay.accentColor = resolvedAccent.nsColor
    refreshOverlay()
    refreshMenu()
    refreshControlPanel()
    calibrationOverlay.start(mode: mode)
  }

  @objc private func requestAccessibility() {
    accessibility.openTrustSettings()
    refreshMenu()
    refreshControlPanel()
  }

  @objc private func openControlPanel() {
    controlPanel.present()
  }

  @objc private func resetCalibration() {
    let alert = NSAlert()
    alert.messageText = "Reset calibration for this display layout?"
    alert.informativeText = "Other saved display layouts will not be changed."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Reset")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }

    mapper.reset()
    displayClassifier.reset()
    latestPrediction = nil
    latestDisplayPrediction = nil
    switchPolicy.resetCandidate()
    cancelAutoReturn()
    clearFeedback()
    calibrationStore.remove(layout: currentLayoutFingerprint)
    refreshOverlay()
    refreshMenu()
    refreshControlPanel()
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }
}
