import AppKit
import TopNVCore

/// The objects that live as long as the app. `NSApplication.delegate` is weak, and the status
/// menu keeps the settings and the updater alive.
@MainActor private enum Application {
  static var delegate: AppDelegate?
  static var statusMenu: StatusMenuController?
}

// The app is AppKit only, as MonoPods: the status item is the UI, and there is no SwiftUI scene.
@main enum Entry {
  @MainActor static func main() {
    let application = NSApplication.shared
    // The bundle sets LSUIElement; this also keeps the Dock icon away when run unbundled.
    application.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    Application.delegate = delegate
    application.delegate = delegate
    application.mainMenu = ApplicationMenu.make { NSApp.terminate(nil) }
    application.run()
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let settings = AppSettings()
  let loginItem = LoginItem()
  let menuVisibility = MenuVisibility(
    defaults: .standard, key: AppSettings.showMenuBarIconKey)
  private var overlay: OverlayController?
  /// Explains once per launch how to fix a menu bar that macOS drew grey over the band.
  private var greyBarNotice: GreyBarNoticeCoordinator?
  private let updateConfiguration = UpdateConfiguration(infoDictionary: Bundle.main.infoDictionary)
  private lazy var sparkleUpdater: SparkleUpdater? = {
    guard Bundle.main.bundleURL.pathExtension == "app", updateConfiguration.isValid else {
      return nil
    }
    return SparkleUpdater()
  }()
  lazy var updates = UpdateMenuModel(updater: sparkleUpdater)
  private lazy var updateCoordinator = UpdateCoordinator(
    configuration: updateConfiguration, updater: sparkleUpdater, defaults: .standard,
    ask: { [weak self] reply in
      AutomaticUpdateQuestion.ask { answer in
        reply(answer)
        self?.greyBarNotice?.questionDidClose()
      }
    }, onReady: { [weak self] in self?.updates.updaterDidStart() },
    onFailed: { [weak self] in self?.updates.updaterDidFail() })

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    menuVisibility.setMenuVisible(true)
    return true
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let statusMenu = StatusMenuController(
      settings: settings, loginItem: loginItem, updates: updates, visibility: menuVisibility)
    Application.statusMenu = statusMenu
    let controller = OverlayController(settings: settings)
    controller.start()
    overlay = controller
    sparkleUpdater?.onChange = { [weak self] in self?.updates.updaterDidChange() }
    updateCoordinator.start()
    let monitor = MenuBarConditionsMonitor(
      settings: settings, statusItem: statusMenu.statusItem, visibility: menuVisibility)
    monitor.start()
    let notice = GreyBarNoticeCoordinator(
      source: monitor,
      isQuestionOnScreen: { [weak self] in self?.updateCoordinator.state == .awaitingAnswer },
      show: GreyBarNotice.show)
    notice.start()
    greyBarNotice = notice
  }
}
