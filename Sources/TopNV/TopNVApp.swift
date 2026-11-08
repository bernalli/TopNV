import AppKit
import SwiftUI
import TopNVCore

@main
struct TopNVApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @AppStorage(AppSettings.showMenuBarIconKey) private var showMenuBarIcon = true

  var body: some Scene {
    MenuBarExtra(isInserted: $showMenuBarIcon) {
      SettingsMenu(settings: appDelegate.settings)
    } label: {
      MenuBarLabel()
    }
    .menuBarExtraStyle(.menu)

    Settings {
      SettingsView(settings: appDelegate.settings, loginItem: appDelegate.loginItem)
    }
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
  private var overlay: OverlayController?

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    UserDefaults.standard.set(true, forKey: AppSettings.showMenuBarIconKey)
    return true
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // The bundle sets LSUIElement; this also keeps the Dock icon away when run unbundled.
    NSApp.setActivationPolicy(.accessory)
    let controller = OverlayController(settings: settings)
    controller.start()
    overlay = controller
  }
}

struct SettingsMenu: View {
  @ObservedObject var settings: AppSettings
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    Button("About topNV") { AboutPanel.show() }

    Divider()

    Toggle("Hide Notch", isOn: $settings.hideNotch)
    Toggle("Round Corners", isOn: $settings.roundCorners)
    Menu("Corner Radius") {
      Picker("Corner Radius", selection: $settings.cornerRadius) {
        ForEach(CornerRadiusOption.options(for: settings.cornerRadius)) { option in
          Text(option.title).tag(option.value)
        }
      }
      .pickerStyle(.inline)
    }
    .disabled(!settings.roundCorners)
    Toggle("Corners on All Displays", isOn: $settings.cornersOnAllDisplays)
      .disabled(!settings.roundCorners)

    Divider()

    Button("Settings…") {
      NSApp.activate()
      openSettings()
    }
    .keyboardShortcut(",", modifiers: .command)

    Divider()

    Menu("Help") {
      Button("topNV Help") { open(.help) }
      Button("Release Notes") { open(.releaseNotes) }
      Button("Report an Issue…") { open(.reportIssue) }
      Button("View Source on GitHub") { open(.source) }
    }

    Divider()

    Button("Quit topNV") { NSApp.terminate(nil) }
      .keyboardShortcut("q", modifiers: .command)
  }

  private func open(_ link: AppLink) {
    guard let url = link.url else { return }
    NSWorkspace.shared.open(url)
  }
}
