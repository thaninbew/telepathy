import AppKit

struct ControlPanelState: Equatable {
  let enabled: Bool
  let status: String
  let detail: String
  let accessibilityReady: Bool
}

@MainActor
final class ControlPanelController: NSWindowController {
  var onEnabledChanged: ((Bool) -> Void)?
  var onRequestAccessibility: (() -> Void)?

  private let powerSwitch = NSSwitch()
  private let statusDot = StatusDotView()
  private let statusLabel = NSTextField(labelWithString: "Starting")
  private let detailLabel = NSTextField(wrappingLabelWithString: "Preparing camera tracking.")
  private let permissionButton = NSButton(
    title: "Open Accessibility Settings",
    target: nil,
    action: nil
  )

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 420),
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

  func update(_ state: ControlPanelState) {
    powerSwitch.state = state.enabled ? .on : .off
    statusLabel.stringValue = state.status
    detailLabel.stringValue = state.detail
    permissionButton.isHidden = state.accessibilityReady
    statusDot.color =
      state.enabled && state.accessibilityReady
      ? OverlayStyle.accent
      : OverlayStyle.idle
    statusDot.needsDisplay = true
  }

  private func buildInterface() {
    guard let contentView = window?.contentView else { return }

    let root = NSStackView()
    root.orientation = .vertical
    root.alignment = .leading
    root.spacing = OverlayStyle.space6
    root.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(root)

    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
      root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
      root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 34),
      root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -28),
    ])

    for view in [makeHeader(), makePowerSection(), makeStatusSection(), makeGuide()] {
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
    let image = NSImageView()
    image.image = NSImage(
      systemSymbolName: "eye.circle.fill",
      accessibilityDescription: "Telepathy"
    )
    image.contentTintColor = OverlayStyle.accent
    image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
    image.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      image.widthAnchor.constraint(equalToConstant: 36),
      image.heightAnchor.constraint(equalToConstant: 36),
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

    let header = NSStackView(views: [image, copy])
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = OverlayStyle.space3
    return header
  }

  private func makePowerSection() -> NSView {
    let section = PanelSectionView()
    let title = makeLabel(
      "Focus follows gaze",
      font: .systemFont(ofSize: 16, weight: .semibold),
      color: OverlayStyle.text
    )
    let explanation = makeLabel(
      "Focus the window you look at and move the pointer once.",
      font: .systemFont(ofSize: 12),
      color: OverlayStyle.telemetry
    )
    explanation.maximumNumberOfLines = 2

    let labels = NSStackView(views: [title, explanation])
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = OverlayStyle.space1

    powerSwitch.target = self
    powerSwitch.action = #selector(powerChanged)
    powerSwitch.setAccessibilityLabel("Focus follows gaze")

    let row = NSStackView(views: [labels, powerSwitch])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.distribution = .fill
    row.spacing = OverlayStyle.space4
    pin(row, inside: section)
    return section
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

    let stack = NSStackView(views: [eyebrow, statusRow, detailLabel, permissionButton])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = OverlayStyle.space2
    pin(stack, inside: section)
    return section
  }

  private func makeGuide() -> NSView {
    let text = """
      1  Look at what you click across several desktop areas.
      2  When status says Tracking, look at another window.
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
