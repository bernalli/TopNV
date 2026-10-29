import AppKit
import SwiftUI

@main
struct TopNVApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarScene(settings: appDelegate.settings, loginItem: appDelegate.loginItem)
  }
}

private struct MenuBarScene: Scene {
  @ObservedObject var settings: AppSettings
  let loginItem: LoginItem

  var body: some Scene {
    MenuBarExtra("topNV", systemImage: "menubar.rectangle", isInserted: $settings.showMenuBarIcon) {
      SettingsMenu(settings: settings, loginItem: loginItem)
    }
    .menuBarExtraStyle(.window)
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let settings = AppSettings()
  let loginItem = LoginItem()
  private var overlay: OverlayController?

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    settings.showMenuBarIcon = true
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
  @ObservedObject var loginItem: LoginItem

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Toggle("Hide notch", isOn: $settings.hideNotch)
      Toggle("Round corners", isOn: $settings.roundCorners)

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text("Corner radius")
          Spacer()
          Text("\(Int(settings.cornerRadius.rounded())) pt")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        Slider(value: $settings.cornerRadius, in: AppSettings.radiusRange, step: 1)
      }
      .disabled(!settings.roundCorners)

      Toggle("Corners on all displays", isOn: $settings.cornersOnAllDisplays)
        .disabled(!settings.roundCorners)

      Divider()

      Toggle(
        "Launch at login",
        isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
      if let message = loginItem.errorMessage {
        Text(message)
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      } else if loginItem.needsApproval {
        Text("Allow topNV in System Settings > General > Login Items.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Divider()

      VStack(alignment: .leading, spacing: 4) {
        Toggle(
          "Hide menu bar icon",
          isOn: Binding(
            get: { !settings.showMenuBarIcon }, set: { settings.showMenuBarIcon = !$0 }))
        Text("Open topNV again to bring it back.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Button("Quit topNV") { NSApp.terminate(nil) }
        .keyboardShortcut("q")
    }
    .toggleStyle(.switch)
    .padding(14)
    .frame(width: 260)
    .onAppear { loginItem.refresh() }
  }
}
