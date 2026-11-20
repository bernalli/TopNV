import AppKit
import Combine
import TopNVCore

/// The menu bar item and its native menu, built as in MonoPods.
///
/// The menu is an AppKit `NSMenu` so that information rows can use the secondary label color on
/// macOS 27 (see `InfoRowStyle`) and the open menu can follow changes. Every change of the
/// settings, the login item, the updater or the icon visibility schedules one refresh in the
/// common run loop modes, which include menu tracking.
@MainActor final class StatusMenuController: NSObject, NSMenuDelegate {
  let statusItem: NSStatusItem
  let menu = NSMenu()
  private let settings: AppSettings
  private let loginItem: LoginItem
  private let updates: UpdateMenuModel
  private let visibility: MenuVisibility
  private var renderer: MenuRenderer?
  private var subscriptions: Set<AnyCancellable> = []
  private var visibilityObservation: NSKeyValueObservation?
  private var refreshScheduled = false
  var onLampChanged: (() -> Void)?
  var onEntrancePreview: (() -> Void)?
  private let relativeKey: RelativeMenuBarKey
  private let isTestCopy: Bool

  private static let icon: NSImage? = {
    let image =
      Bundle.main.image(forResource: "MenuBarIcon")
      ?? NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: nil)
    image?.isTemplate = true
    image?.size = NSSize(width: 18, height: 18)
    return image
  }()

  init(
    settings: AppSettings, loginItem: LoginItem, updates: UpdateMenuModel,
    visibility: MenuVisibility, isTestCopy: Bool = false, relativeKey: RelativeMenuBarKey? = nil
  ) {
    self.relativeKey = relativeKey ?? .shared
    self.isTestCopy = isTestCopy
    self.settings = settings
    self.loginItem = loginItem
    self.updates = updates
    self.visibility = visibility
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()
    renderer = MenuRenderer { [weak self] command in self?.perform(command) }
    // The user may Command-drag the item out of the menu bar, as in MonoPods.
    statusItem.behavior = .removalAllowed
    statusItem.button?.image = Self.icon
    statusItem.button?.setAccessibilityTitle(Localizer.appName)
    menu.delegate = self
    statusItem.menu = menu
    refresh()
    // A removal by the user is written back like the Hide Menu Bar Icon setting.
    visibilityObservation = statusItem.observe(\.isVisible, options: [.new]) { [weak self] _, change in
      guard let visible = change.newValue else { return }
      MainActor.assumeIsolated {
        guard let self, visible != self.visibility.isVisible else { return }
        self.visibility.requestMenuVisible(visible)
      }
    }
    // All four objects publish on the main actor.
    for publisher in [
      settings.objectWillChange.eraseToAnyPublisher(),
      loginItem.objectWillChange.eraseToAnyPublisher(),
      updates.objectWillChange.eraseToAnyPublisher(),
      visibility.objectWillChange.eraseToAnyPublisher()
    ] {
      publisher.sink { [weak self] _ in
        MainActor.assumeIsolated { self?.scheduleRefresh() }
      }.store(in: &subscriptions)
    }
  }

  /// `objectWillChange` fires before the new value is stored, so the refresh runs on the next
  /// turn of the run loop. Several changes in one turn give one refresh.
  private func scheduleRefresh() {
    guard !refreshScheduled else { return }
    refreshScheduled = true
    RunLoop.main.perform(inModes: [.common]) { [weak self] in
      MainActor.assumeIsolated { self?.refresh() }
    }
    // A scheduled block does not wake a sleeping run loop by itself.
    CFRunLoopWakeUp(CFRunLoopGetMain())
  }

  func refresh() {
    refreshScheduled = false
    var rows = MenuLayout.rows(for: state)
    if isTestCopy, let index = rows.firstIndex(where: { $0.id == "separator.app" }) {
      rows.insert(.lampOnly(enabled: relativeKey.lampMode == .only), at: index)
      rows.insert(.lampKey(selected: relativeKey.lampKey), at: index)
      rows.insert(.lampUnderKey(enabled: relativeKey.lampEnabled), at: index)
      rows.insert(.relativeKey(available: relativeKey.available, enabled: relativeKey.enabled), at: index)
    }
    renderer?.apply(rows, to: menu)
    if statusItem.isVisible != visibility.isVisible { statusItem.isVisible = visibility.isVisible }
  }

  private var state: MenuState {
    MenuState(
      hideNotch: settings.hideNotch, roundCorners: settings.roundCorners,
      cornersOnAllDisplays: settings.cornersOnAllDisplays, launchAtLogin: loginItem.isEnabled,
      loginNeedsApproval: loginItem.needsApproval, loginError: loginItem.errorMessage,
      updates: updates.items, isTestCopy: isTestCopy)
  }

  /// The login item does not publish approval changes made in System Settings; opening the menu
  /// reads them again.
  func menuNeedsUpdate(_ menu: NSMenu) {
    loginItem.refresh()
    refresh()
  }

  func perform(_ command: MenuCommand) {
    switch command {
    case .hideNotch, .roundCorners, .cornersOnAllDisplays, .launchAtLogin, .automaticUpdates, .hideMenuBarIcon:
      performSetting(command)
    case .checkForUpdates: updates.checkForUpdates()
    case .about: AboutWindowController.shared.show()
    case .reportIssue:
      if let url = AppLink.reportIssue.url { NSWorkspace.shared.open(url) }
    case .quit: NSApp.terminate(nil)
    case .previewCalm:
      guard isTestCopy, settings.hideNotch else { return }
      onEntrancePreview?()
    case .lampUnderKey, .lampOnly:
      guard isTestCopy else { return }
      let present = onLampChanged ?? {}
      if command == .lampOnly {
        relativeKey.toggleLampOnly(present: present)
      } else {
        relativeKey.toggleLamp(present: present)
      }
      refresh()
    case .lampKey1, .lampKey2, .lampKey3, .lampKey4, .lampKey5:
      guard isTestCopy, let preset = LampKeyPreset.choices.first(where: { $0.command == command }) else { return }
      relativeKey.selectLampKey(preset)
      refresh()
    case .relativeKey:
      guard isTestCopy else { return }
      relativeKey.toggle()
      refresh()
    }
  }

  private func performSetting(_ command: MenuCommand) {
    switch command {
    case .hideNotch: settings.hideNotch.toggle()
    case .roundCorners: settings.roundCorners.toggle()
    case .cornersOnAllDisplays: settings.cornersOnAllDisplays.toggle()
    case .launchAtLogin: loginItem.setEnabled(!loginItem.isEnabled)
    case .automaticUpdates: updates.setAutomaticallyChecks(!updates.automaticallyChecksForUpdates)
    case .hideMenuBarIcon: visibility.setMenuVisible(false)
    default: assertionFailure("Expected a settings command")
    }
  }
}
