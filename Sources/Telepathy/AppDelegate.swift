import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let controller = TelepathyController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)
    controller.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    controller.stop()
  }
}
