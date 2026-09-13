import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let controller = TelepathyController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    configureApplicationMenu()
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.applicationIconImage = TelepathyLogoView.applicationIconImage()
    controller.start()
    controller.presentControlPanel()
  }

  func applicationWillTerminate(_ notification: Notification) {
    controller.stop()
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    controller.presentControlPanel()
    return false
  }

  private func configureApplicationMenu() {
    let mainMenu = NSMenu()
    let applicationItem = NSMenuItem()
    let applicationMenu = NSMenu(title: "Telepathy")

    let aboutItem = NSMenuItem(
      title: "About Telepathy",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: ""
    )
    aboutItem.target = NSApplication.shared
    applicationMenu.addItem(aboutItem)
    applicationMenu.addItem(.separator())

    let openItem = NSMenuItem(
      title: "Open Telepathy",
      action: #selector(openControlPanel),
      keyEquivalent: "o"
    )
    openItem.target = self
    applicationMenu.addItem(openItem)

    let hideItem = NSMenuItem(
      title: "Hide Telepathy",
      action: #selector(NSApplication.hide(_:)),
      keyEquivalent: "h"
    )
    hideItem.target = NSApplication.shared
    applicationMenu.addItem(hideItem)
    applicationMenu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: "Quit Telepathy",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    quitItem.target = NSApplication.shared
    applicationMenu.addItem(quitItem)

    applicationItem.submenu = applicationMenu
    mainMenu.addItem(applicationItem)

    let windowItem = NSMenuItem()
    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(
      withTitle: "Close",
      action: #selector(NSWindow.performClose(_:)),
      keyEquivalent: "w"
    )
    windowMenu.addItem(
      withTitle: "Minimize",
      action: #selector(NSWindow.performMiniaturize(_:)),
      keyEquivalent: "m"
    )
    windowItem.submenu = windowMenu
    mainMenu.addItem(windowItem)
    NSApplication.shared.windowsMenu = windowMenu

    NSApplication.shared.mainMenu = mainMenu
  }

  @objc private func openControlPanel() {
    controller.presentControlPanel()
  }
}
