import AppKit

@MainActor
final class ControlPanelPreviewAppDelegate: NSObject, NSApplicationDelegate {
  private let panel = ControlPanelController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    let presenceMode =
      ProcessInfo.processInfo.environment["TELEPATHY_UI_PREVIEW_PRESENCE"]
      .flatMap(AppPresenceMode.init(rawValue:)) ?? .standard
    NSApplication.shared.setActivationPolicy(presenceMode.activationPolicy)
    switch ProcessInfo.processInfo.environment["TELEPATHY_UI_PREVIEW_APPEARANCE"] {
    case "light":
      panel.window?.appearance = NSAppearance(named: .aqua)
    case "dark":
      panel.window?.appearance = NSAppearance(named: .darkAqua)
    default:
      break
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
    state.activationMode =
      ProcessInfo.processInfo.environment["TELEPATHY_UI_PREVIEW_ACTIVATION"]
      .flatMap(ActivationMode.init(rawValue:)) ?? .automatic
    state.explicitActivationOverridesMouseMovement = true
    state.shortcut = .defaultValue
    state.switchDelay = 0.09
    state.autoReturnInterval = 0
    state.accentTheme = AccentTheme(source: .system, customColor: .gold)
    state.resolvedAccent = AccentColor(color: .controlAccentColor)
    state.quickRecenterEnabled = true
    state.appPresenceMode = presenceMode
    panel.onAppPresenceChanged = { mode in
      NSApplication.shared.setActivationPolicy(mode.activationPolicy)
    }
    panel.update(state)
    if let rawPage = ProcessInfo.processInfo.environment["TELEPATHY_UI_PREVIEW_PAGE"],
      let page = Int(rawPage)
    {
      panel.selectPage(page)
    }
    panel.present()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}
