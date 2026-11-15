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
        settings: delegate.settings, loginItem: delegate.loginItem, visibility: visibility, updates: delegate.updates)
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
      Image(nsImage: icon).accessibilityLabel("TopNV")
    } else {
      Image(systemName: "menubar.rectangle").accessibilityLabel("TopNV")
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
  private let updateConfiguration = UpdateConfiguration(infoDictionary: Bundle.main.infoDictionary)
  private lazy var sparkleUpdater: SparkleUpdater? = {
    guard Bundle.main.bundleURL.pathExtension == "app", updateConfiguration.isValid else { return nil }
    return SparkleUpdater()
  }()
  lazy var updates = UpdateMenuModel(updater: sparkleUpdater)
  private lazy var updateCoordinator = UpdateCoordinator(
    configuration: updateConfiguration, updater: sparkleUpdater, defaults: .standard,
    ask: AutomaticUpdateQuestion.ask, onReady: { [weak self] in self?.updates.updaterDidStart() })

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
    sparkleUpdater?.onChange = { [weak self] in self?.updates.updaterDidChange() }
    updateCoordinator.start()
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
  @ObservedObject var updates: UpdateMenuModel
  private let localizer = Localizer.main
  private let appName = Localizer.appName
  private let version = AppVersion(
    shortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
    build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)

  var body: some View {
    Section("TopNV") {
      let status = MenuStatus(hideNotch: settings.hideNotch, roundCorners: settings.roundCorners)
      Label(status.title, systemImage: status.symbol)
      Toggle(isOn: $settings.hideNotch) {
        Label(localizer(.hideNotch), systemImage: "menubar.rectangle")
      }
      Toggle(isOn: $settings.roundCorners) {
        Label(localizer(.roundCorners), systemImage: "rectangle")
      }
    }
    Menu {
      info(localizer(settings.cornersOnAllDisplays ? .appliesToAllDisplays : .appliesToBuiltInDisplay))
      info(localizer(.permissionsNoneRequired))
      info(localizer(.requiresMacOS))
    } label: {
      Label(localizer(.details), systemImage: "info.circle")
    }
    Menu {
      Toggle(isOn: $settings.cornersOnAllDisplays) {
        Label(localizer(.cornersOnAllDisplays), systemImage: "display.2")
      }
      .disabled(!settings.roundCorners)
      Divider()
      Toggle(isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })) {
        Label(localizer(.launchAtLogin), systemImage: "power")
      }
      if let message = loginItem.errorMessage {
        info(message)
      } else if loginItem.needsApproval {
        info(localizer(.loginItemApproval, appName))
      }
      Toggle(isOn: Binding(
        get: { updates.automaticallyChecksForUpdates }, set: { updates.setAutomaticallyChecks($0) }
      )) {
        Label(localizer(.automaticUpdates), systemImage: "arrow.triangle.2.circlepath")
      }
      .disabled(!updates.isAvailable)
      Divider()
      Toggle(isOn: Binding(
        get: { !visibility.isVisible }, set: { visibility.setMenuVisible(!$0) }
      )) {
        Label(localizer(.hideMenuBarIcon), systemImage: "menubar.rectangle")
      }
      info(localizer(.hideMenuBarIconCaption, appName))
    } label: {
      Label(localizer(.options), systemImage: "gearshape")
    }
    Divider()
    info(version.title)
    Button(localizer(.checkForUpdates)) { updates.checkForUpdates() }
      .disabled(!updates.canCheckForUpdates)
    Button(localizer(.about, appName)) { AboutWindowController.shared.show() }
    Button(localizer(.reportIssue)) { open(.reportIssue) }
    Divider()
    Button(localizer(.quit, appName)) { NSApp.terminate(nil) }
      .keyboardShortcut("q", modifiers: .command)
  }

  @ViewBuilder private func info(_ text: String) -> some View {
    ForEach(Array(MenuText.lines(text).enumerated()), id: \.offset) { _, line in
      Text(verbatim: line)
    }
  }

  private func open(_ link: AppLink) {
    guard let url = link.url else { return }
    NSWorkspace.shared.open(url)
  }
}
