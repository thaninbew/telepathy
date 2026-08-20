import AppKit

struct ControlPanelState: Equatable {
  let enabled: Bool
  let status: String
  let detail: String
  let gazeIndicatorEnabled: Bool
  let calibrationButtonTitle: String
  let calibrationEnabled: Bool
  let accessibilityReady: Bool
  var screenFeedbackEnabled: Bool = true
  var activationMode: ActivationMode = .automatic
  var shortcut: ShortcutBinding = .defaultValue
  var switchDelay: TimeInterval = 0.09
  var autoReturnInterval: TimeInterval = 0
  var accentTheme: AccentTheme = .defaultValue
  var resolvedAccent: AccentColor = .gold
  var quickRecenterEnabled: Bool = false
}

@MainActor
final class ControlPanelController: NSWindowController, NSWindowDelegate {
  var onEnabledChanged: ((Bool) -> Void)?
  var onGazeIndicatorChanged: ((Bool) -> Void)?
  var onScreenFeedbackChanged: ((Bool) -> Void)?
  var onActivationModeChanged: ((ActivationMode) -> Void)?
  var onShortcutChanged: ((ShortcutBinding) -> Void)?
  var onSwitchDelayChanged: ((TimeInterval) -> Void)?
  var onAutoReturnChanged: ((TimeInterval) -> Void)?
  var onAccentSourceChanged: ((AccentThemeSource) -> Void)?
  var onCustomAccentChanged: ((AccentColor) -> Void)?
  var onCalibrate: (() -> Void)?
  var onQuickRecenter: (() -> Void)?
  var onRequestAccessibility: (() -> Void)?

  private let powerSwitch = AccentSwitch()
  private let gazeIndicatorSwitch = AccentSwitch()
  private let screenFeedbackSwitch = AccentSwitch()
  private let activationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let activationDetail = NSTextField(wrappingLabelWithString: "")
  private let shortcutButton = NSButton(title: "Left Shift", target: nil, action: nil)
  private let switchDelayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let autoReturnPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let accentSourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let accentColorWell = NSColorWell()
  private let headerImage = NSImageView()
  private let statusDot = StatusDotView()
  private let statusLabel = NSTextField(labelWithString: "Starting")
  private let detailLabel = NSTextField(wrappingLabelWithString: "Preparing camera tracking.")
  private let permissionButton = NSButton(
    title: "Open Accessibility Settings",
    target: nil,
    action: nil
  )
  private let calibrationButton = NSButton(title: "Calibrate…", target: nil, action: nil)
  private let quickRecenterButton = NSButton(title: "Quick Recenter…", target: nil, action: nil)
  private var currentState: ControlPanelState?
  private var shortcutMonitor: Any?

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 468, height: 780),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Telepathy"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isReleasedWhenClosed = false
    window.backgroundColor = OverlayStyle.background
    window.appearance = NSAppearance(named: .darkAqua)
    window.center()
    window.setFrameAutosaveName("TelepathyControlPanel")
    super.init(window: window)
    window.delegate = self
    buildInterface()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  func present() {
    guard let window else { return }
    showWindow(nil)
    NSApplication.shared.activate()
    window.makeKeyAndOrderFront(nil)
  }

  func dismiss() {
    finishShortcutRecording(with: nil)
    window?.orderOut(nil)
  }

  func windowWillClose(_ notification: Notification) {
    finishShortcutRecording(with: nil)
  }

  func update(_ state: ControlPanelState) {
    guard state != currentState else { return }
    currentState = state
    powerSwitch.state = state.enabled ? .on : .off
    gazeIndicatorSwitch.state = state.gazeIndicatorEnabled ? .on : .off
    screenFeedbackSwitch.state = state.screenFeedbackEnabled ? .on : .off
    rebuildActivationMenu(shortcutName: state.shortcut.displayName)
    selectActivationMode(state.activationMode)
    activationDetail.stringValue = state.activationMode.detail(
      shortcutName: state.shortcut.displayName)
    if shortcutMonitor == nil { shortcutButton.title = state.shortcut.displayName }
    selectPopup(switchDelayPopup, value: state.switchDelay)
    selectPopup(autoReturnPopup, value: state.autoReturnInterval)
    selectAccentSource(state.accentTheme.source)
    accentColorWell.color = state.accentTheme.customColor.nsColor
    accentColorWell.isEnabled = state.accentTheme.source == .custom
    applyAccent(state.resolvedAccent.nsColor)
    statusLabel.stringValue = state.status
    detailLabel.stringValue = state.detail
    calibrationButton.title = state.calibrationButtonTitle
    calibrationButton.isEnabled = state.calibrationEnabled
    quickRecenterButton.isEnabled = state.quickRecenterEnabled
    permissionButton.isHidden = state.accessibilityReady
    statusDot.color =
      state.enabled && state.accessibilityReady
      ? state.resolvedAccent.nsColor
      : OverlayStyle.idle
    statusDot.needsDisplay = true
  }

  private func buildInterface() {
    guard let contentView = window?.contentView else { return }

    let root = NSStackView()
    root.orientation = .vertical
    root.alignment = .leading
    root.spacing = 20
    root.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(root)

    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
      root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
      root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
      root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -28),
    ])

    for view in [makeHeader(), makeControlsSection(), makeStatusSection(), makeGuide()] {
      root.addArrangedSubview(view)
      view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }

    let shortcut = makeLabel(
      "⌘⌥ESC  EMERGENCY PAUSE",
      font: .monospacedSystemFont(ofSize: 11, weight: .medium),
      color: OverlayStyle.telemetry
    )
    shortcut.alignment = .center
    root.addArrangedSubview(shortcut)
    shortcut.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
  }

  private func makeHeader() -> NSView {
    headerImage.image = NSImage(
      systemSymbolName: "eye.circle.fill",
      accessibilityDescription: "Telepathy"
    )
    headerImage.contentTintColor = OverlayStyle.accent
    headerImage.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
    headerImage.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      headerImage.widthAnchor.constraint(equalToConstant: 36),
      headerImage.heightAnchor.constraint(equalToConstant: 36),
    ])

    let title = makeLabel(
      "Telepathy",
      font: .systemFont(ofSize: 28, weight: .semibold),
      color: OverlayStyle.text
    )
    let subtitle = makeLabel(
      "Attention chooses focus.",
      font: .systemFont(ofSize: 13),
      color: OverlayStyle.telemetry
    )
    let copy = NSStackView(views: [title, subtitle])
    copy.orientation = .vertical
    copy.alignment = .leading
    copy.spacing = OverlayStyle.space1

    let header = NSStackView(views: [headerImage, copy])
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = OverlayStyle.space3
    return header
  }

  private func makeControlsSection() -> NSView {
    let section = PanelSectionView()
    powerSwitch.target = self
    powerSwitch.action = #selector(powerChanged)
    powerSwitch.setAccessibilityLabel("Focus follows gaze")

    gazeIndicatorSwitch.target = self
    gazeIndicatorSwitch.action = #selector(gazeIndicatorChanged)
    gazeIndicatorSwitch.setAccessibilityLabel("Show experimental gaze indicator")

    screenFeedbackSwitch.target = self
    screenFeedbackSwitch.action = #selector(screenFeedbackChanged)
    screenFeedbackSwitch.setAccessibilityLabel("Show screen bloom")

    activationPopup.target = self
    activationPopup.action = #selector(activationChanged)
    activationPopup.setAccessibilityLabel("Activation method")

    shortcutButton.target = self
    shortcutButton.action = #selector(beginShortcutRecording)
    shortcutButton.bezelStyle = .rounded
    shortcutButton.setAccessibilityLabel("Activation shortcut")

    configurePopup(
      switchDelayPopup,
      values: [("Instant", 0), ("90 ms", 0.09), ("150 ms", 0.15), ("250 ms", 0.25),
        ("400 ms", 0.4), ("650 ms", 0.65)],
      action: #selector(switchDelayChanged),
      accessibilityLabel: "Switch delay"
    )
    configurePopup(
      autoReturnPopup,
      values: [("Off", 0), ("1 second", 1), ("2 seconds", 2), ("3 seconds", 3),
        ("5 seconds", 5)],
      action: #selector(autoReturnChanged),
      accessibilityLabel: "Auto-return"
    )

    for source in AccentThemeSource.allCases {
      accentSourcePopup.addItem(withTitle: source.title)
      accentSourcePopup.lastItem?.representedObject = source.rawValue
    }
    accentSourcePopup.target = self
    accentSourcePopup.action = #selector(accentSourceChanged)
    accentSourcePopup.setAccessibilityLabel("Accent color source")

    accentColorWell.target = self
    accentColorWell.action = #selector(customAccentChanged)
    accentColorWell.supportsAlpha = false
    accentColorWell.setAccessibilityLabel("Custom accent color")
    if #available(macOS 13.0, *) {
      accentColorWell.colorWellStyle = .minimal
    }

    let focusRow = makeToggleRow(
      title: "Display handoff",
      explanation: "Turn toward another screen to restore its recent window and pointer.",
      control: powerSwitch
    )
    let activationRow = makeActivationRow()
    let shortcutRow = makeSettingRow(
      title: "Keyboard shortcut",
      explanation: "Observed without blocking the key. Click it to record another.",
      control: shortcutButton
    )
    let delayRow = makeSettingRow(
      title: "Switch delay",
      explanation: "How long the target screen must remain stable before activation.",
      control: switchDelayPopup
    )
    let autoReturnRow = makeSettingRow(
      title: "Auto-return",
      explanation: "Return to the previous screen unless physical mouse input adopts this one.",
      control: autoReturnPopup
    )
    let accentControls = NSStackView(views: [accentSourcePopup, accentColorWell])
    accentControls.orientation = .horizontal
    accentControls.alignment = .centerY
    accentControls.spacing = OverlayStyle.space2
    let accentRow = makeSettingRow(
      title: "Accent color",
      explanation: "Use the macOS accent or one custom color across feedback and controls.",
      control: accentControls
    )
    let feedbackRow = makeToggleRow(
      title: "Screen bloom",
      explanation: "Briefly show an armed, dwelling, or completed screen handoff.",
      control: screenFeedbackSwitch
    )
    let indicatorRow = makeToggleRow(
      title: "Experimental gaze indicator",
      explanation: "Show the fine eye-and-head estimate used by the research mode.",
      control: gazeIndicatorSwitch
    )
    let dividers = (0..<7).map { _ -> NSBox in
      let divider = NSBox()
      divider.boxType = .separator
      return divider
    }
    let rows: [NSView] = [
      focusRow, dividers[0], activationRow, dividers[1], shortcutRow, dividers[2], delayRow,
      dividers[3], autoReturnRow, dividers[4], accentRow, dividers[5], feedbackRow, dividers[6],
      indicatorRow,
    ]
    let stack = NSStackView(
      views: rows
    )
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    for view in rows {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    pin(stack, inside: section)
    return section
  }

  private func makeActivationRow() -> NSView {
    let titleLabel = makeLabel(
      "Activation",
      font: .systemFont(ofSize: 16, weight: .semibold),
      color: OverlayStyle.text
    )
    activationDetail.font = .systemFont(ofSize: 12)
    activationDetail.textColor = OverlayStyle.telemetry
    activationDetail.maximumNumberOfLines = 2
    activationDetail.stringValue = ActivationMode.automatic.detail(
      shortcutName: ShortcutBinding.defaultValue.displayName)

    let labels = NSStackView(views: [titleLabel, activationDetail])
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = OverlayStyle.space1

    let row = NSStackView(views: [labels, activationPopup])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.distribution = .fill
    row.spacing = OverlayStyle.space4
    return row
  }

  private func makeToggleRow(
    title: String,
    explanation: String,
    control: AccentSwitch
  ) -> NSView {
    let titleLabel = makeLabel(
      title,
      font: .systemFont(ofSize: 16, weight: .semibold),
      color: OverlayStyle.text
    )
    let explanationLabel = makeLabel(
      explanation,
      font: .systemFont(ofSize: 12),
      color: OverlayStyle.telemetry
    )
    explanationLabel.maximumNumberOfLines = 2

    let labels = NSStackView(views: [titleLabel, explanationLabel])
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = OverlayStyle.space1

    let row = NSStackView(views: [labels, control])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.distribution = .fill
    row.spacing = OverlayStyle.space4
    return row
  }

  private func makeSettingRow(
    title: String,
    explanation: String,
    control: NSView
  ) -> NSView {
    let titleLabel = makeLabel(
      title,
      font: .systemFont(ofSize: 16, weight: .semibold),
      color: OverlayStyle.text
    )
    let explanationLabel = makeLabel(
      explanation,
      font: .systemFont(ofSize: 12),
      color: OverlayStyle.telemetry
    )
    explanationLabel.maximumNumberOfLines = 2

    let labels = NSStackView(views: [titleLabel, explanationLabel])
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = OverlayStyle.space1

    control.setContentHuggingPriority(.required, for: .horizontal)
    let row = NSStackView(views: [labels, control])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.distribution = .fill
    row.spacing = OverlayStyle.space4
    return row
  }

  private func makeStatusSection() -> NSView {
    let section = PanelSectionView()
    let eyebrow = makeLabel(
      "STATUS",
      font: .systemFont(ofSize: 10, weight: .semibold),
      color: OverlayStyle.telemetry
    )
    eyebrow.attributedStringValue = trackedString(
      "STATUS",
      font: eyebrow.font!,
      color: OverlayStyle.telemetry
    )

    statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
    statusLabel.textColor = OverlayStyle.text
    statusLabel.lineBreakMode = .byTruncatingTail

    detailLabel.font = .systemFont(ofSize: 12)
    detailLabel.textColor = OverlayStyle.telemetry
    detailLabel.maximumNumberOfLines = 3

    statusDot.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      statusDot.widthAnchor.constraint(equalToConstant: 8),
      statusDot.heightAnchor.constraint(equalToConstant: 8),
    ])
    let statusRow = NSStackView(views: [statusDot, statusLabel])
    statusRow.orientation = .horizontal
    statusRow.alignment = .centerY
    statusRow.spacing = OverlayStyle.space2

    permissionButton.target = self
    permissionButton.action = #selector(requestAccessibility)
    permissionButton.bezelStyle = .rounded
    permissionButton.contentTintColor = OverlayStyle.accent
    permissionButton.controlSize = .large

    calibrationButton.target = self
    calibrationButton.action = #selector(calibrate)
    calibrationButton.bezelStyle = .rounded
    calibrationButton.contentTintColor = OverlayStyle.accent
    calibrationButton.controlSize = .large
    calibrationButton.setAccessibilityLabel("Calibrate gaze tracking")

    quickRecenterButton.target = self
    quickRecenterButton.action = #selector(quickRecenter)
    quickRecenterButton.bezelStyle = .rounded
    quickRecenterButton.controlSize = .large
    quickRecenterButton.setAccessibilityLabel("Quickly recenter head tracking")

    let actions = NSStackView(views: [permissionButton, calibrationButton, quickRecenterButton])
    actions.orientation = .horizontal
    actions.alignment = .centerY
    actions.spacing = OverlayStyle.space2

    let stack = NSStackView(views: [eyebrow, statusRow, detailLabel, actions])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = OverlayStyle.space2
    pin(stack, inside: section)
    return section
  }

  private func makeGuide() -> NSView {
    let text = """
      1  Run Full Calibration across every active display.
      2  Turn toward another screen, then use your chosen activation.
      3  Move the physical mouse whenever you want manual control.
      """
    let guide = makeLabel(
      text,
      font: .monospacedSystemFont(ofSize: 11, weight: .regular),
      color: OverlayStyle.telemetry
    )
    guide.maximumNumberOfLines = 0
    return guide
  }

  private func pin(_ view: NSView, inside container: NSView) {
    view.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(view)
    NSLayoutConstraint.activate([
      view.leadingAnchor.constraint(
        equalTo: container.leadingAnchor, constant: OverlayStyle.space4),
      view.trailingAnchor.constraint(
        equalTo: container.trailingAnchor,
        constant: -OverlayStyle.space4
      ),
      view.topAnchor.constraint(equalTo: container.topAnchor, constant: OverlayStyle.space4),
      view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -OverlayStyle.space4),
    ])
  }

  private func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = font
    label.textColor = color
    return label
  }

  private func trackedString(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
    NSAttributedString(
      string: text,
      attributes: [
        .font: font,
        .foregroundColor: color,
        .kern: 1.4,
      ]
    )
  }

  @objc private func powerChanged() {
    onEnabledChanged?(powerSwitch.state == .on)
  }

  @objc private func gazeIndicatorChanged() {
    onGazeIndicatorChanged?(gazeIndicatorSwitch.state == .on)
  }

  @objc private func screenFeedbackChanged() {
    onScreenFeedbackChanged?(screenFeedbackSwitch.state == .on)
  }

  @objc private func activationChanged() {
    guard let rawValue = activationPopup.selectedItem?.representedObject as? String,
      let mode = ActivationMode(rawValue: rawValue)
    else { return }
    let shortcutName = currentState?.shortcut.displayName ?? ShortcutBinding.defaultValue.displayName
    activationDetail.stringValue = mode.detail(shortcutName: shortcutName)
    onActivationModeChanged?(mode)
  }

  @objc private func beginShortcutRecording() {
    finishShortcutRecording(with: nil)
    shortcutButton.title = "Press a key…"
    shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
      [weak self] event in
      guard let self else { return event }
      if event.type == .keyDown, event.keyCode == 53 {
        self.finishShortcutRecording(with: nil)
        return nil
      }
      guard let binding = Self.shortcutBinding(from: event) else { return event }
      self.finishShortcutRecording(with: binding)
      return nil
    }
    window?.makeFirstResponder(shortcutButton)
  }

  @objc private func switchDelayChanged() {
    guard let value = switchDelayPopup.selectedItem?.representedObject as? NSNumber else { return }
    onSwitchDelayChanged?(value.doubleValue)
  }

  @objc private func autoReturnChanged() {
    guard let value = autoReturnPopup.selectedItem?.representedObject as? NSNumber else { return }
    onAutoReturnChanged?(value.doubleValue)
  }

  @objc private func accentSourceChanged() {
    guard let rawValue = accentSourcePopup.selectedItem?.representedObject as? String,
      let source = AccentThemeSource(rawValue: rawValue)
    else { return }
    accentColorWell.isEnabled = source == .custom
    onAccentSourceChanged?(source)
  }

  @objc private func customAccentChanged() {
    onCustomAccentChanged?(AccentColor(color: accentColorWell.color))
  }

  private func finishShortcutRecording(with binding: ShortcutBinding?) {
    if let shortcutMonitor {
      NSEvent.removeMonitor(shortcutMonitor)
      self.shortcutMonitor = nil
    }
    if let binding {
      shortcutButton.title = binding.displayName
      onShortcutChanged?(binding)
    } else {
      shortcutButton.title = currentState?.shortcut.displayName ?? ShortcutBinding.defaultValue.displayName
    }
  }

  private func rebuildActivationMenu(shortcutName: String) {
    let titles = ActivationMode.allCases.map { $0.title(shortcutName: shortcutName) }
    guard activationPopup.itemTitles != titles else { return }
    activationPopup.removeAllItems()
    for mode in ActivationMode.allCases {
      activationPopup.addItem(withTitle: mode.title(shortcutName: shortcutName))
      activationPopup.lastItem?.representedObject = mode.rawValue
    }
  }

  private func selectActivationMode(_ mode: ActivationMode) {
    guard let index = activationPopup.itemArray.firstIndex(where: {
      ($0.representedObject as? String) == mode.rawValue
    }) else { return }
    activationPopup.selectItem(at: index)
  }

  private func configurePopup(
    _ popup: NSPopUpButton,
    values: [(String, Double)],
    action: Selector,
    accessibilityLabel: String
  ) {
    for (title, value) in values {
      popup.addItem(withTitle: title)
      popup.lastItem?.representedObject = NSNumber(value: value)
    }
    popup.target = self
    popup.action = action
    popup.setAccessibilityLabel(accessibilityLabel)
  }

  private func selectPopup(_ popup: NSPopUpButton, value: TimeInterval) {
    guard let index = popup.itemArray.firstIndex(where: {
      guard let number = $0.representedObject as? NSNumber else { return false }
      return abs(number.doubleValue - value) < 0.001
    }) else { return }
    popup.selectItem(at: index)
  }

  private func selectAccentSource(_ source: AccentThemeSource) {
    guard let index = accentSourcePopup.itemArray.firstIndex(where: {
      ($0.representedObject as? String) == source.rawValue
    }) else { return }
    accentSourcePopup.selectItem(at: index)
  }

  private func applyAccent(_ accent: NSColor) {
    headerImage.contentTintColor = accent
    powerSwitch.accentColor = accent
    screenFeedbackSwitch.accentColor = accent
    gazeIndicatorSwitch.accentColor = accent
    permissionButton.contentTintColor = accent
    calibrationButton.contentTintColor = accent
    quickRecenterButton.contentTintColor = accent
  }

  private static func shortcutBinding(from event: NSEvent) -> ShortcutBinding? {
    let keyCode = Int64(event.keyCode)
    if event.type == .flagsChanged {
      guard modifierIsDown(keyCode: keyCode, flags: event.modifierFlags),
        let name = modifierName(keyCode: keyCode)
      else { return nil }
      return ShortcutBinding(keyCode: keyCode, displayName: name)
    }
    guard event.type == .keyDown, !event.isARepeat else { return nil }
    let name = keyName(keyCode: keyCode, characters: event.charactersIgnoringModifiers)
    return ShortcutBinding(keyCode: keyCode, displayName: name)
  }

  private static func modifierIsDown(keyCode: Int64, flags: NSEvent.ModifierFlags) -> Bool {
    switch keyCode {
    case 56, 60: flags.contains(.shift)
    case 59, 62: flags.contains(.control)
    case 58, 61: flags.contains(.option)
    case 54, 55: flags.contains(.command)
    case 57: flags.contains(.capsLock)
    default: false
    }
  }

  private static func modifierName(keyCode: Int64) -> String? {
    switch keyCode {
    case 56: "Left Shift"
    case 60: "Right Shift"
    case 59: "Left Control"
    case 62: "Right Control"
    case 58: "Left Option"
    case 61: "Right Option"
    case 55: "Left Command"
    case 54: "Right Command"
    case 57: "Caps Lock"
    default: nil
    }
  }

  private static func keyName(keyCode: Int64, characters: String?) -> String {
    switch keyCode {
    case 36: return "Return"
    case 48: return "Tab"
    case 49: return "Space"
    case 51: return "Delete"
    case 115: return "Home"
    case 116: return "Page Up"
    case 117: return "Forward Delete"
    case 119: return "End"
    case 121: return "Page Down"
    case 123: return "Left Arrow"
    case 124: return "Right Arrow"
    case 125: return "Down Arrow"
    case 126: return "Up Arrow"
    default:
      let cleaned = characters?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
      return cleaned.isEmpty ? "Key \(keyCode)" : cleaned
    }
  }

  @objc private func calibrate() {
    onCalibrate?()
  }

  @objc private func quickRecenter() {
    onQuickRecenter?()
  }

  @objc private func requestAccessibility() {
    onRequestAccessibility?()
  }
}

private final class PanelSectionView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = OverlayStyle.surface.cgColor
    layer?.borderColor = OverlayStyle.border.cgColor
    layer?.borderWidth = 1
    layer?.cornerRadius = OverlayStyle.panelCornerRadius
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }
}

private final class StatusDotView: NSView {
  var color = OverlayStyle.idle

  override func draw(_ dirtyRect: NSRect) {
    color.setFill()
    NSBezierPath(ovalIn: bounds).fill()
  }
}
