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
  var explicitActivationOverridesMouseMovement = true
  var shortcut: ShortcutBinding = .defaultValue
  var switchDelay: TimeInterval = 0.09
  var autoReturnInterval: TimeInterval = 0
  var accentTheme: AccentTheme = .defaultValue
  var resolvedAccent: AccentColor = .gold
  var quickRecenterEnabled: Bool = false
}

@MainActor
final class ControlPanelController: NSWindowController, NSWindowDelegate {
  private enum Page: Int, CaseIterable {
    case focus
    case calibration
    case feedback

    var title: String {
      switch self {
      case .focus: "Focus"
      case .calibration: "Calibration"
      case .feedback: "Feedback"
      }
    }

    var symbolName: String {
      switch self {
      case .focus: "eye"
      case .calibration: "scope"
      case .feedback: "sparkles"
      }
    }
  }

  var onEnabledChanged: ((Bool) -> Void)?
  var onGazeIndicatorChanged: ((Bool) -> Void)?
  var onScreenFeedbackChanged: ((Bool) -> Void)?
  var onActivationModeChanged: ((ActivationMode) -> Void)?
  var onExplicitActivationMouseOverrideChanged: ((Bool) -> Void)?
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
  private let explicitActivationMouseOverrideSwitch = AccentSwitch()
  private let activationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let activationDetail = NSTextField(wrappingLabelWithString: "")
  private let shortcutButton = NSButton(title: "Left Shift", target: nil, action: nil)
  private let switchDelayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let autoReturnPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let accentSourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let accentColorWell = NSColorWell()
  private let logoView = TelepathyLogoView()
  private let sourceList = NSTableView()
  private let tabView = NSTabView()
  private let statusDot = StatusDotView()
  private let sidebarStatusDot = StatusDotView()
  private let statusLabel = NSTextField(labelWithString: "Starting")
  private let sidebarStatusLabel = NSTextField(wrappingLabelWithString: "Starting")
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
      contentRect: NSRect(origin: .zero, size: TelepathyComponent.windowSize),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Telepathy"
    window.isReleasedWhenClosed = false
    window.backgroundColor = TelepathySemantic.background
    window.minSize = TelepathyComponent.minimumWindowSize
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

  func selectPageForPreview(_ index: Int) {
    guard index >= 0, index < Page.allCases.count else { return }
    sourceList.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    tabView.selectTabViewItem(at: index)
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
    explicitActivationMouseOverrideSwitch.state =
      state.explicitActivationOverridesMouseMovement ? .on : .off
    updateActivationDependentControls(for: state.activationMode)
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
    accentColorWell.isHidden = state.accentTheme.source != .custom
    applyAccent(TelepathySemantic.panelAccent(for: state.accentTheme))
    statusLabel.stringValue = state.status
    sidebarStatusLabel.stringValue = state.enabled ? state.status : "Paused"
    detailLabel.stringValue = state.detail
    calibrationButton.title = state.calibrationButtonTitle
    calibrationButton.isEnabled = state.calibrationEnabled
    quickRecenterButton.isEnabled = state.quickRecenterEnabled
    permissionButton.isHidden = state.accessibilityReady
    let statusColor =
      state.enabled && state.accessibilityReady
      ? TelepathySemantic.panelAccent(for: state.accentTheme)
      : TelepathySemantic.secondaryText
    statusDot.color = statusColor
    sidebarStatusDot.color = statusColor
    statusDot.needsDisplay = true
    sidebarStatusDot.needsDisplay = true
  }

  private func buildInterface() {
    guard let contentView = window?.contentView else { return }

    let sidebar = makeSidebar()
    let main = makeMainContent()
    let divider = SidebarDividerView()
    let shell = NSStackView(views: [sidebar, divider, main])
    shell.orientation = .horizontal
    shell.alignment = .top
    shell.distribution = .fill
    shell.spacing = 0
    shell.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(shell)

    NSLayoutConstraint.activate([
      shell.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      shell.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      shell.topAnchor.constraint(equalTo: contentView.topAnchor),
      shell.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      sidebar.widthAnchor.constraint(equalToConstant: TelepathyComponent.sidebarWidth),
      sidebar.heightAnchor.constraint(equalTo: shell.heightAnchor),
      divider.widthAnchor.constraint(equalToConstant: TelepathyComponent.dividerWidth),
      divider.heightAnchor.constraint(equalTo: shell.heightAnchor),
      main.heightAnchor.constraint(equalTo: shell.heightAnchor),
    ])
  }

  private func makeSidebar() -> NSView {
    let sidebar = SidebarBackgroundView()

    logoView.translatesAutoresizingMaskIntoConstraints = false
    let title = makeLabel(
      "Telepathy",
      font: TelepathyComponent.sidebarTitleFont,
      color: TelepathySemantic.text
    )
    let detail = makeLabel(
      "Focus utility",
      font: TelepathyComponent.sidebarDetailFont,
      color: TelepathySemantic.secondaryText
    )
    let brandCopy = NSStackView(views: [title, detail])
    brandCopy.orientation = .vertical
    brandCopy.alignment = .leading
    brandCopy.spacing = TelepathyPrimitive.Space.x1
    let brand = NSStackView(views: [logoView, brandCopy])
    brand.orientation = .horizontal
    brand.alignment = .centerY
    brand.spacing = TelepathyPrimitive.Space.x3
    brand.translatesAutoresizingMaskIntoConstraints = false
    sidebar.addSubview(brand)

    sourceList.headerView = nil
    sourceList.style = .sourceList
    sourceList.rowHeight = TelepathyComponent.sourceListRowHeight
    sourceList.backgroundColor = .clear
    sourceList.allowsEmptySelection = false
    sourceList.delegate = self
    sourceList.dataSource = self
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Navigation"))
    column.resizingMask = .autoresizingMask
    sourceList.addTableColumn(column)

    let sourceScroll = NSScrollView()
    sourceScroll.drawsBackground = false
    sourceScroll.hasVerticalScroller = false
    sourceScroll.documentView = sourceList
    sourceScroll.translatesAutoresizingMaskIntoConstraints = false
    sidebar.addSubview(sourceScroll)

    configureStatusDot(sidebarStatusDot)
    sidebarStatusLabel.font = TelepathyComponent.sidebarDetailFont
    sidebarStatusLabel.textColor = TelepathySemantic.secondaryText
    sidebarStatusLabel.maximumNumberOfLines = 2
    sidebarStatusLabel.lineBreakMode = .byWordWrapping
    let status = NSStackView(views: [sidebarStatusDot, sidebarStatusLabel])
    status.orientation = .horizontal
    status.alignment = .centerY
    status.spacing = TelepathyPrimitive.Space.x2
    let emergency = makeLabel(
      "⌘⌥Esc pauses instantly",
      font: TelepathyComponent.sidebarDetailFont,
      color: TelepathySemantic.secondaryText
    )
    let footer = NSStackView(views: [status, emergency])
    footer.orientation = .vertical
    footer.alignment = .leading
    footer.spacing = TelepathyPrimitive.Space.x2
    footer.translatesAutoresizingMaskIntoConstraints = false
    sidebar.addSubview(footer)

    NSLayoutConstraint.activate([
      logoView.widthAnchor.constraint(equalToConstant: TelepathyComponent.logoSize),
      logoView.heightAnchor.constraint(equalToConstant: TelepathyComponent.logoSize),
      brand.leadingAnchor.constraint(
        equalTo: sidebar.leadingAnchor, constant: TelepathyComponent.sidebarInset),
      brand.trailingAnchor.constraint(
        lessThanOrEqualTo: sidebar.trailingAnchor, constant: -TelepathyComponent.sidebarInset),
      brand.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: TelepathyPrimitive.Space.x6),
      sourceScroll.leadingAnchor.constraint(
        equalTo: sidebar.leadingAnchor, constant: TelepathyComponent.sidebarInset),
      sourceScroll.trailingAnchor.constraint(
        equalTo: sidebar.trailingAnchor, constant: -TelepathyComponent.sidebarInset),
      sourceScroll.topAnchor.constraint(
        equalTo: brand.bottomAnchor, constant: TelepathyPrimitive.Space.x6),
      sourceScroll.bottomAnchor.constraint(
        equalTo: footer.topAnchor, constant: -TelepathyPrimitive.Space.x4),
      footer.leadingAnchor.constraint(
        equalTo: sidebar.leadingAnchor, constant: TelepathyComponent.sidebarInset),
      footer.trailingAnchor.constraint(
        lessThanOrEqualTo: sidebar.trailingAnchor, constant: -TelepathyComponent.sidebarInset),
      footer.bottomAnchor.constraint(
        equalTo: sidebar.bottomAnchor, constant: -TelepathyPrimitive.Space.x4),
    ])

    sourceList.reloadData()
    sourceList.selectRowIndexes(IndexSet(integer: Page.focus.rawValue), byExtendingSelection: false)
    return sidebar
  }

  private func makeMainContent() -> NSView {
    let main = NSView()

    tabView.tabViewType = .noTabsNoBorder
    tabView.translatesAutoresizingMaskIntoConstraints = false
    main.addSubview(tabView)

    let pages: [(Page, NSView)] = [
      (.focus, makeFocusPage()),
      (.calibration, makeCalibrationPage()),
      (.feedback, makeFeedbackPage()),
    ]
    for (page, view) in pages {
      let item = NSTabViewItem(identifier: page)
      item.view = view
      tabView.addTabViewItem(item)
    }
    tabView.selectTabViewItem(at: Page.focus.rawValue)

    NSLayoutConstraint.activate([
      tabView.leadingAnchor.constraint(equalTo: main.leadingAnchor),
      tabView.trailingAnchor.constraint(equalTo: main.trailingAnchor),
      tabView.topAnchor.constraint(equalTo: main.topAnchor),
      tabView.bottomAnchor.constraint(equalTo: main.bottomAnchor),
    ])
    return main
  }

  private func configureControls() {
    powerSwitch.target = self
    powerSwitch.action = #selector(powerChanged)
    powerSwitch.setAccessibilityLabel("Focus follows gaze")

    gazeIndicatorSwitch.target = self
    gazeIndicatorSwitch.action = #selector(gazeIndicatorChanged)
    gazeIndicatorSwitch.setAccessibilityLabel("Show experimental gaze indicator")

    screenFeedbackSwitch.target = self
    screenFeedbackSwitch.action = #selector(screenFeedbackChanged)
    screenFeedbackSwitch.setAccessibilityLabel("Show screen shine")

    explicitActivationMouseOverrideSwitch.target = self
    explicitActivationMouseOverrideSwitch.action = #selector(explicitActivationMouseOverrideChanged)
    explicitActivationMouseOverrideSwitch.setAccessibilityLabel(
      "Allow explicit activation while moving the mouse"
    )

    activationPopup.target = self
    activationPopup.action = #selector(activationChanged)
    activationPopup.setAccessibilityLabel("Activation method")

    shortcutButton.target = self
    shortcutButton.action = #selector(beginShortcutRecording)
    shortcutButton.bezelStyle = .rounded
    shortcutButton.setAccessibilityLabel("Activation shortcut")

    configurePopup(
      switchDelayPopup,
      values: [
        ("Instant", 0), ("90 ms", 0.09), ("150 ms", 0.15), ("250 ms", 0.25),
        ("400 ms", 0.4), ("650 ms", 0.65),
      ],
      action: #selector(switchDelayChanged),
      accessibilityLabel: "Switch delay"
    )
    configurePopup(
      autoReturnPopup,
      values: [
        ("Off", 0), ("1 second", 1), ("2 seconds", 2), ("3 seconds", 3),
        ("5 seconds", 5),
      ],
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
  }

  private func makeFocusPage() -> NSView {
    configureControls()

    let powerLabel = makeLabel(
      "Telepathy",
      font: TelepathyComponent.statusFont,
      color: TelepathySemantic.text
    )
    let powerControl = NSStackView(views: [powerLabel, powerSwitch])
    powerControl.orientation = .horizontal
    powerControl.alignment = .centerY
    powerControl.spacing = TelepathyPrimitive.Space.x2

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
    let mouseOverrideRow = makeToggleRow(
      title: "Activate while moving pointer",
      explanation: "Keyboard or middle mouse can switch even while the pointer is moving.",
      control: explicitActivationMouseOverrideSwitch
    )
    let autoReturnRow = makeSettingRow(
      title: "Auto-return",
      explanation: "Return to the previous screen unless physical mouse input adopts this one.",
      control: autoReturnPopup
    )
    let activationGroup = makeLabeledSettingsGroup(
      title: "Activation",
      rows: [activationRow, shortcutRow, mouseOverrideRow]
    )
    let behaviorGroup = makeLabeledSettingsGroup(
      title: "Handoff behavior",
      rows: [delayRow, autoReturnRow]
    )
    return makePage(
      title: "Focus",
      detail: "Move attention between displays naturally.",
      trailing: powerControl,
      sections: [activationGroup, behaviorGroup]
    )
  }

  private func makeCalibrationPage() -> NSView {
    statusLabel.font = TelepathyComponent.rowTitleFont
    statusLabel.textColor = TelepathySemantic.text
    statusLabel.lineBreakMode = .byTruncatingTail
    detailLabel.font = TelepathyComponent.rowDetailFont
    detailLabel.textColor = TelepathySemantic.secondaryText
    detailLabel.maximumNumberOfLines = 3
    configureStatusDot(statusDot)

    let statusCopy = NSStackView(views: [statusLabel, detailLabel])
    statusCopy.orientation = .vertical
    statusCopy.alignment = .leading
    statusCopy.spacing = TelepathyPrimitive.Space.x1
    let statusRow = NSStackView(views: [statusDot, statusCopy])
    statusRow.orientation = .horizontal
    statusRow.alignment = .centerY
    statusRow.spacing = TelepathyPrimitive.Space.x3

    permissionButton.target = self
    permissionButton.action = #selector(requestAccessibility)
    permissionButton.bezelStyle = .rounded
    permissionButton.controlSize = .large

    calibrationButton.target = self
    calibrationButton.action = #selector(calibrate)
    calibrationButton.bezelStyle = .rounded
    calibrationButton.controlSize = .large
    calibrationButton.keyEquivalent = "\r"
    calibrationButton.setAccessibilityLabel("Run full calibration")

    quickRecenterButton.target = self
    quickRecenterButton.action = #selector(quickRecenter)
    quickRecenterButton.bezelStyle = .rounded
    quickRecenterButton.controlSize = .large
    quickRecenterButton.setAccessibilityLabel("Quickly recenter head tracking")

    let actions = NSStackView(views: [calibrationButton, quickRecenterButton, permissionButton])
    actions.orientation = .horizontal
    actions.alignment = .centerY
    actions.spacing = TelepathyPrimitive.Space.x2

    let statusGroup = makeSettingsGroup(rows: [
      makeContainedRow(statusRow),
      makeContainedRow(actions),
    ])
    let guideGroup = makeSettingsGroup(rows: [
      makeGuideRow(
        number: 1, text: "Look at each target while staying in a natural working posture."),
      makeGuideRow(
        number: 2, text: "Full Calibration samples every active display and normal movement."),
      makeGuideRow(
        number: 3,
        text: "Quick Recenter adjusts for a posture change without replacing the profile."),
    ])
    return makePage(
      title: "Calibration",
      detail: "Keep screen selection accurate as your setup changes.",
      trailing: nil,
      sections: [statusGroup, guideGroup]
    )
  }

  private func makeFeedbackPage() -> NSView {
    let accentControls = NSStackView(views: [accentSourcePopup, accentColorWell])
    accentControls.orientation = .horizontal
    accentControls.alignment = .centerY
    accentControls.spacing = TelepathyPrimitive.Space.x2
    let accentRow = makeSettingRow(
      title: "Accent color",
      explanation: "Follow macOS or choose one restrained signal color.",
      control: accentControls
    )
    let feedbackRow = makeToggleRow(
      title: "Screen shine",
      explanation: "Briefly confirm an armed, dwelling, or completed handoff.",
      control: screenFeedbackSwitch
    )
    let indicatorRow = makeToggleRow(
      title: "Debug gaze area",
      explanation: "Show the smoothed eye-and-head estimate while testing.",
      control: gazeIndicatorSwitch
    )
    let group = makeSettingsGroup(rows: [feedbackRow, indicatorRow, accentRow])
    return makePage(
      title: "Feedback",
      detail: "Keep confirmation visible, brief, and quiet.",
      trailing: nil,
      sections: [group]
    )
  }

  private func makeActivationRow() -> NSView {
    let titleLabel = makeLabel(
      "Method",
      font: TelepathyComponent.rowTitleFont,
      color: TelepathySemantic.text
    )
    activationDetail.font = TelepathyComponent.rowDetailFont
    activationDetail.textColor = TelepathySemantic.secondaryText
    activationDetail.maximumNumberOfLines = 2
    activationDetail.stringValue = ActivationMode.automatic.detail(
      shortcutName: ShortcutBinding.defaultValue.displayName)

    let labels = NSStackView(views: [titleLabel, activationDetail])
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = TelepathyPrimitive.Space.x1

    let row = NSStackView(views: [labels, activationPopup])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.distribution = .fill
    row.spacing = TelepathyComponent.rowGap
    return makeContainedRow(row)
  }

  private func makeToggleRow(
    title: String,
    explanation: String,
    control: AccentSwitch
  ) -> NSView {
    let titleLabel = makeLabel(
      title,
      font: TelepathyComponent.rowTitleFont,
      color: TelepathySemantic.text
    )
    let explanationLabel = makeLabel(
      explanation,
      font: TelepathyComponent.rowDetailFont,
      color: TelepathySemantic.secondaryText
    )
    explanationLabel.maximumNumberOfLines = 2

    let labels = NSStackView(views: [titleLabel, explanationLabel])
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = TelepathyPrimitive.Space.x1

    let row = NSStackView(views: [labels, control])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.distribution = .fill
    row.spacing = TelepathyComponent.rowGap
    return makeContainedRow(row)
  }

  private func makeSettingRow(
    title: String,
    explanation: String,
    control: NSView
  ) -> NSView {
    let titleLabel = makeLabel(
      title,
      font: TelepathyComponent.rowTitleFont,
      color: TelepathySemantic.text
    )
    let explanationLabel = makeLabel(
      explanation,
      font: TelepathyComponent.rowDetailFont,
      color: TelepathySemantic.secondaryText
    )
    explanationLabel.maximumNumberOfLines = 2

    let labels = NSStackView(views: [titleLabel, explanationLabel])
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = TelepathyPrimitive.Space.x1

    control.setContentHuggingPriority(.required, for: .horizontal)
    let row = NSStackView(views: [labels, control])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.distribution = .fill
    row.spacing = TelepathyComponent.rowGap
    return makeContainedRow(row)
  }

  private func makePage(
    title: String,
    detail: String,
    trailing: NSView?,
    sections: [NSView]
  ) -> NSView {
    let page = NSView()

    let titleLabel = makeLabel(
      title,
      font: TelepathyComponent.pageTitleFont,
      color: TelepathySemantic.text
    )
    let detailLabel = makeLabel(
      detail,
      font: TelepathyComponent.pageDetailFont,
      color: TelepathySemantic.secondaryText
    )
    let copy = NSStackView(views: [titleLabel, detailLabel])
    copy.orientation = .vertical
    copy.alignment = .leading
    copy.spacing = TelepathyPrimitive.Space.x1

    var headerViews: [NSView] = [copy]
    if let trailing {
      trailing.setContentHuggingPriority(.required, for: .horizontal)
      headerViews.append(trailing)
    }
    let header = NSStackView(views: headerViews)
    header.orientation = .horizontal
    header.alignment = .centerY
    header.distribution = .fill
    header.spacing = TelepathyPrimitive.Space.x4

    let root = NSStackView(views: [header] + sections)
    root.orientation = .vertical
    root.alignment = .leading
    root.spacing = TelepathyComponent.sectionGap
    root.translatesAutoresizingMaskIntoConstraints = false
    page.addSubview(root)
    for view in [header] + sections {
      view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }

    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(
        equalTo: page.leadingAnchor, constant: TelepathyComponent.contentInset),
      root.trailingAnchor.constraint(
        equalTo: page.trailingAnchor, constant: -TelepathyComponent.contentInset),
      root.topAnchor.constraint(equalTo: page.topAnchor, constant: TelepathyComponent.contentInset),
      root.bottomAnchor.constraint(
        lessThanOrEqualTo: page.bottomAnchor, constant: -TelepathyComponent.contentInset),
    ])
    return page
  }

  private func makeSettingsGroup(rows: [NSView]) -> NSView {
    let group = SettingsGroupView()
    let arranged: [NSView] = rows.enumerated().flatMap { index, row in
      guard index < rows.count - 1 else { return [row] }
      let divider = NSBox()
      divider.boxType = .separator
      return [row, divider]
    }
    let stack = NSStackView(views: arranged)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    group.addSubview(stack)
    for view in arranged {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: group.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: group.trailingAnchor),
      stack.topAnchor.constraint(equalTo: group.topAnchor),
      stack.bottomAnchor.constraint(equalTo: group.bottomAnchor),
    ])
    return group
  }

  private func makeLabeledSettingsGroup(title: String, rows: [NSView]) -> NSView {
    let titleLabel = makeLabel(
      title,
      font: TelepathyComponent.rowTitleFont,
      color: TelepathySemantic.secondaryText
    )
    let group = makeSettingsGroup(rows: rows)
    let section = NSStackView(views: [titleLabel, group])
    section.orientation = .vertical
    section.alignment = .leading
    section.spacing = TelepathyPrimitive.Space.x2
    group.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
    return section
  }

  private func makeContainedRow(_ content: NSView) -> NSView {
    let row = NSView()
    content.translatesAutoresizingMaskIntoConstraints = false
    row.addSubview(content)
    NSLayoutConstraint.activate([
      row.heightAnchor.constraint(
        greaterThanOrEqualToConstant: TelepathyComponent.rowMinimumHeight),
      content.leadingAnchor.constraint(
        equalTo: row.leadingAnchor, constant: TelepathyComponent.rowInset),
      content.trailingAnchor.constraint(
        equalTo: row.trailingAnchor, constant: -TelepathyComponent.rowInset),
      content.topAnchor.constraint(equalTo: row.topAnchor, constant: TelepathyPrimitive.Space.x3),
      content.bottomAnchor.constraint(
        equalTo: row.bottomAnchor, constant: -TelepathyPrimitive.Space.x3),
    ])
    return row
  }

  private func makeGuideRow(number: Int, text: String) -> NSView {
    let image = NSImageView()
    image.image = NSImage(
      systemSymbolName: "\(number).circle",
      accessibilityDescription: "Step \(number)"
    )
    image.contentTintColor = TelepathySemantic.secondaryText
    image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    let label = makeLabel(
      text,
      font: TelepathyComponent.rowDetailFont,
      color: TelepathySemantic.secondaryText
    )
    label.maximumNumberOfLines = 2
    let row = NSStackView(views: [image, label])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = TelepathyPrimitive.Space.x3
    return makeContainedRow(row)
  }

  private func configureStatusDot(_ dot: StatusDotView) {
    dot.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      dot.widthAnchor.constraint(equalToConstant: TelepathyComponent.statusDotSize),
      dot.heightAnchor.constraint(equalToConstant: TelepathyComponent.statusDotSize),
    ])
  }

  private func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = font
    label.textColor = color
    return label
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

  @objc private func explicitActivationMouseOverrideChanged() {
    onExplicitActivationMouseOverrideChanged?(explicitActivationMouseOverrideSwitch.state == .on)
  }

  @objc private func activationChanged() {
    guard let rawValue = activationPopup.selectedItem?.representedObject as? String,
      let mode = ActivationMode(rawValue: rawValue)
    else { return }
    let shortcutName =
      currentState?.shortcut.displayName ?? ShortcutBinding.defaultValue.displayName
    activationDetail.stringValue = mode.detail(shortcutName: shortcutName)
    updateActivationDependentControls(for: mode)
    onActivationModeChanged?(mode)
  }

  private func updateActivationDependentControls(for mode: ActivationMode) {
    let supportsExplicitOverride = mode == .keyboard || mode == .mouse
    explicitActivationMouseOverrideSwitch.isEnabled = supportsExplicitOverride
    explicitActivationMouseOverrideSwitch.toolTip =
      supportsExplicitOverride
      ? nil
      : "Choose Keyboard or Middle Mouse activation to use this setting."
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
    accentColorWell.isHidden = source != .custom
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
      shortcutButton.title =
        currentState?.shortcut.displayName ?? ShortcutBinding.defaultValue.displayName
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
    guard
      let index = activationPopup.itemArray.firstIndex(where: {
        ($0.representedObject as? String) == mode.rawValue
      })
    else { return }
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
    guard
      let index = popup.itemArray.firstIndex(where: {
        guard let number = $0.representedObject as? NSNumber else { return false }
        return abs(number.doubleValue - value) < 0.001
      })
    else { return }
    popup.selectItem(at: index)
  }

  private func selectAccentSource(_ source: AccentThemeSource) {
    guard
      let index = accentSourcePopup.itemArray.firstIndex(where: {
        ($0.representedObject as? String) == source.rawValue
      })
    else { return }
    accentSourcePopup.selectItem(at: index)
  }

  private func applyAccent(_ accent: NSColor) {
    logoView.accentColor = accent
    powerSwitch.accentColor = accent
    explicitActivationMouseOverrideSwitch.accentColor = accent
    screenFeedbackSwitch.accentColor = accent
    gazeIndicatorSwitch.accentColor = accent
    calibrationButton.bezelColor = accent
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

@MainActor
extension ControlPanelController: NSTableViewDataSource, NSTableViewDelegate {
  func numberOfRows(in tableView: NSTableView) -> Int {
    Page.allCases.count
  }

  func tableView(
    _ tableView: NSTableView,
    viewFor tableColumn: NSTableColumn?,
    row: Int
  ) -> NSView? {
    guard let page = Page(rawValue: row) else { return nil }
    let cell = NSTableCellView()
    let image = NSImageView()
    image.image = NSImage(
      systemSymbolName: page.symbolName,
      accessibilityDescription: nil
    )
    image.contentTintColor = TelepathySemantic.secondaryText
    image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
    let label = NSTextField(labelWithString: page.title)
    label.font = TelepathyComponent.rowTitleFont
    label.textColor = TelepathySemantic.text
    let stack = NSStackView(views: [image, label])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = TelepathyPrimitive.Space.x2
    stack.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(
        equalTo: cell.leadingAnchor, constant: TelepathyPrimitive.Space.x2),
      stack.trailingAnchor.constraint(
        lessThanOrEqualTo: cell.trailingAnchor, constant: -TelepathyPrimitive.Space.x2),
      stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let selected = max(sourceList.selectedRow, 0)
    guard Page(rawValue: selected) != nil,
      selected < tabView.numberOfTabViewItems
    else { return }
    tabView.selectTabViewItem(at: selected)
  }
}

private final class SettingsGroupView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    refreshAppearance()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refreshAppearance()
  }

  private func refreshAppearance() {
    layer?.backgroundColor = TelepathySemantic.surface.cgColor
    layer?.borderColor = TelepathySemantic.border.cgColor
    layer?.borderWidth = TelepathyComponent.dividerWidth
    layer?.cornerRadius = TelepathyComponent.groupRadius
  }
}

private final class SidebarBackgroundView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    refreshAppearance()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refreshAppearance()
  }

  private func refreshAppearance() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = TelepathySemantic.sidebar.cgColor
    }
  }
}

private final class SidebarDividerView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    refreshAppearance()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refreshAppearance()
  }

  private func refreshAppearance() {
    layer?.backgroundColor = TelepathySemantic.border.cgColor
  }
}

private final class StatusDotView: NSView {
  var color = TelepathySemantic.secondaryText

  override func draw(_ dirtyRect: NSRect) {
    color.setFill()
    NSBezierPath(ovalIn: bounds).fill()
  }
}
