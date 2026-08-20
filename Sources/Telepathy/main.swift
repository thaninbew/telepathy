import AppKit

let application = NSApplication.shared
let delegate: NSApplicationDelegate =
  ProcessInfo.processInfo.environment["TELEPATHY_UI_PREVIEW"] == "1"
  ? ControlPanelPreviewAppDelegate()
  : AppDelegate()
application.delegate = delegate
application.run()
