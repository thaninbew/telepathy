import AppKit
import Foundation

enum AppPresenceMode: String, CaseIterable {
  case standard
  case menuBarOnly
  case dockOnly
  case hidden

  static let defaultsKey = "telepathy.appPresenceMode"

  var title: String {
    switch self {
    case .standard: "Standard"
    case .menuBarOnly: "Menu Bar Only"
    case .dockOnly: "Dock Only"
    case .hidden: "Hidden"
    }
  }

  var detail: String {
    switch self {
    case .standard: "Shown in the Dock, Command-Tab, and menu bar."
    case .menuBarOnly: "Shown only in the menu bar, without Dock or Command-Tab presence."
    case .dockOnly: "Shown in the Dock and Command-Tab, without a menu-bar icon."
    case .hidden: "No persistent icon. Reopen Telepathy from Spotlight or Applications."
    }
  }

  var showsMenuBarItem: Bool {
    self == .standard || self == .menuBarOnly
  }

  var activationPolicy: NSApplication.ActivationPolicy {
    switch self {
    case .standard, .dockOnly: .regular
    case .menuBarOnly, .hidden: .accessory
    }
  }

  static func stored(in defaults: UserDefaults = .standard) -> AppPresenceMode {
    defaults.string(forKey: defaultsKey).flatMap(AppPresenceMode.init(rawValue:)) ?? .standard
  }
}
