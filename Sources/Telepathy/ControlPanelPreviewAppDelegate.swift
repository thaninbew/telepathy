import AppKit

@MainActor
final class ControlPanelPreviewAppDelegate: NSObject, NSApplicationDelegate {
  private let panel = ControlPanelController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.regular)
    if ProcessInfo.processInfo.environment["TELEPATHY_UI_PREVIEW_APPEARANCE"] == "light" {
      panel.window?.appearance = NSAppearance(named: .aqua)
    } else {
      panel.window?.appearance = NSAppearance(named: .darkAqua)
    }
    var state = ControlPanelState(
      enabled: true,
      status: "Tracking",
      detail: "Turn toward another display. Telepathy restores that display context only.",
      gazeIndicatorEnabled: false,
      calibrationButtonTitle: "Full Calibration…",
      calibrationEnabled: true,
      accessibilityReady: true
    )
    state.screenFeedbackEnabled = true
    state.activationMode = .automatic
    state.shortcut = .defaultValue
    state.switchDelay = 0.09
    state.autoReturnInterval = 0
    state.accentTheme = AccentTheme(source: .system, customColor: .gold)
    state.resolvedAccent = AccentColor(color: .controlAccentColor)
    state.quickRecenterEnabled = true
    panel.update(state)
    if let rawPage = ProcessInfo.processInfo.environment["TELEPATHY_UI_PREVIEW_PAGE"],
      let page = Int(rawPage)
    {
      panel.selectPageForPreview(page)
    }
    panel.present()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}
