import AppKit
import SwiftUI
import TopNVCore

@main
struct TopNVApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    TopNVMenuScene(delegate: appDelegate, visibility: appDelegate.menuVisibility)
  }
}

private struct TopNVMenuScene: Scene {
  let delegate: AppDelegate
  @ObservedObject var visibility: MenuVisibility

  var body: some Scene {
    MenuBarExtra(isInserted: Binding(
      get: { visibility.isVisible },
      set: { visibility.requestMenuVisible($0) }
    )) {
      SettingsMenu(
        settings: delegate.settings, loginItem: delegate.loginItem, visibility: visibility)
        .labelStyle(.titleAndIcon)
    } label: {
      MenuBarLabel()
    }
    .menuBarExtraStyle(.menu)
  }
}

/// The menu bar icon from the app bundle, or an SF Symbol when run unbundled.
private struct MenuBarLabel: View {
  private static let icon: NSImage? = {
    guard let image = Bundle.main.image(forResource: "MenuBarIcon") else { return nil }
    image.isTemplate = true
    image.size = NSSize(width: 18, height: 18)
    return image
  }()

  var body: some View {
    if let icon = Self.icon {
      Image(nsImage: icon).accessibilityLabel("topNV")
    } else {
      Image(systemName: "menubar.rectangle").accessibilityLabel("topNV")
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let settings = AppSettings()
  let loginItem = LoginItem()
  let menuVisibility = MenuVisibility(
    defaults: .standard, key: AppSettings.showMenuBarIconKey)
  private var overlay: OverlayController?

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    menuVisibility.setMenuVisible(true)
    return true
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // The bundle sets LSUIElement; this also keeps the Dock icon away when run unbundled.
    NSApp.setActivationPolicy(.accessory)
    NotificationCenter.default.addObserver(
      self, selector: #selector(menuDidBeginTracking(_:)),
      name: NSMenu.didBeginTrackingNotification, object: nil)
    let controller = OverlayController(settings: settings)
    controller.start()
    overlay = controller
  }

  @objc private func menuDidBeginTracking(_ notification: Notification) {
    // Native menus do not reliably call onAppear. Publish after AppKit starts tracking,
    // outside the scene update, so external login-item approval changes reach the next menu.
    Task { @MainActor [weak self] in self?.loginItem.refresh() }
  }
}

struct SettingsMenu: View {
  @ObservedObject var settings: AppSettings
  @ObservedObject var loginItem: LoginItem
  @ObservedObject var visibility: MenuVisibility
  private let version = AppVersion(
    shortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
    build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)

  var body: some View {
    Section("topNV") {
      let status = MenuStatus(hideNotch: settings.hideNotch, roundCorners: settings.roundCorners)
      Label(status.title, systemImage: status.symbol)
        .foregroundStyle(.secondary)
      Toggle(isOn: $settings.hideNotch) {
        Label("Hide Notch", systemImage: "menubar.rectangle")
      }
      Toggle(isOn: $settings.roundCorners) {
        Label("Round Corners", systemImage: "rectangle")
      }
      Menu {
        Picker("Corner Radius", selection: $settings.cornerRadius) {
          ForEach(CornerRadiusOption.options(for: settings.cornerRadius)) { option in
            Text(option.title).tag(option.value)
          }
        }
        .pickerStyle(.inline)
      } label: {
        Label("Corner Radius", systemImage: "ruler")
      }
      .disabled(!settings.roundCorners)
    }
    Menu {
      info("Corner Radius: \(CornerRadiusOption(value: settings.cornerRadius, isCustom: false).title)")
      info(settings.cornersOnAllDisplays ? "Applies To: All Displays" : "Applies To: Built-in Display")
      info("Permissions: None Required")
      info("Requires macOS 14 or Later")
      Divider()
      Button("View Source on GitHub") { open(.source) }
      Button("Release Notes") { open(.releaseNotes) }
      Button("Report an Issue…") { open(.reportIssue) }
    } label: {
      Label("Details", systemImage: "info.circle")
    }
    Menu {
      Toggle("Corners on All Displays", isOn: $settings.cornersOnAllDisplays)
        .disabled(!settings.roundCorners)
      Divider()
      Toggle(isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })) {
        Label("Launch at Login", systemImage: "power")
      }
      if let message = loginItem.errorMessage {
        info(message)
      } else if loginItem.needsApproval {
        info("Allow topNV in System Settings > General > Login Items.")
      }
      Divider()
      Toggle(isOn: Binding(
        get: { !visibility.isVisible }, set: { visibility.setMenuVisible(!$0) }
      )) {
        Label("Hide Menu Bar Icon", systemImage: "menubar.rectangle")
      }
      info("Open topNV again to bring it back.")
    } label: {
      Label("Options", systemImage: "gearshape")
    }
    Divider()
    info(version.title)
    Button("About topNV") { AboutPanel.show() }
    Divider()
    Button("Quit topNV") { NSApp.terminate(nil) }
      .keyboardShortcut("q", modifiers: .command)
  }

  @ViewBuilder private func info(_ text: String) -> some View {
    ForEach(Array(MenuText.lines(text).enumerated()), id: \.offset) { _, line in
      Text(line).foregroundStyle(.secondary)
    }
  }

  private func open(_ link: AppLink) {
    guard let url = link.url else { return }
    NSWorkspace.shared.open(url)
  }
}
