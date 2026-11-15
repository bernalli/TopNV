import AppKit
import TopNVCore

/// The main menu of the accessory app, as in MonoPods. The application menu holds one item, Quit
/// TopNV with Command-Q; the app has no SwiftUI scene, so nothing adds Settings, window or file
/// commands. AppKit sends Command-Q to this menu only while the app is active, for example with
/// the About window in front.
enum ApplicationMenu {
  @MainActor static func make(
    localizer: Localizer = .main, quit: @escaping @MainActor () -> Void
  ) -> NSMenu {
    let applicationMenu = NSMenu(title: Localizer.appName)
    applicationMenu.addItem(
      ActionMenuItem(
        title: localizer(.quit, Localizer.appName), keyEquivalent: "q", perform: quit))
    let applicationItem = NSMenuItem()
    applicationItem.submenu = applicationMenu
    let mainMenu = NSMenu()
    mainMenu.addItem(applicationItem)
    return mainMenu
  }
}

/// A menu item that runs its closure. A menu item holds its target weakly, so the item is its own
/// target: the menu that retains the item also keeps the action alive.
private final class ActionMenuItem: NSMenuItem {
  private let perform: @MainActor () -> Void

  init(title: String, keyEquivalent: String, perform: @escaping @MainActor () -> Void) {
    self.perform = perform
    super.init(title: title, action: #selector(run(_:)), keyEquivalent: keyEquivalent)
    target = self
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("ActionMenuItem is created in code")
  }

  // AppKit sends menu actions on the main thread.
  @MainActor @objc private func run(_ sender: NSMenuItem) { perform() }
}
