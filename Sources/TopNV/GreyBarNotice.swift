import AppKit
import TopNVCore

/// The notice about the grey menu bar, presented like the first-launch question: a window
/// without a modal session. The notice keeps itself alive until the first click; later clicks
/// do nothing.
@MainActor final class GreyBarNotice: NSObject {
  let alert = NSAlert()
  private let present: @MainActor (NSWindow, Bool) -> Void
  private let openSettings: @MainActor () -> Void
  private var reply: ((GreyBarNoticeAnswer) -> Void)?
  /// Holds the notice while it waits for its answer.
  private var retained: GreyBarNotice?

  /// The entry point of `GreyBarNoticeCoordinator`.
  static func show(_ reply: @escaping (GreyBarNoticeAnswer) -> Void) {
    GreyBarNotice(reply: reply).show()
  }

  init(
    localizer: Localizer = .main,
    present: @escaping @MainActor (NSWindow, Bool) -> Void = AppleStyleUpdateDriver.present,
    openSettings: @escaping @MainActor () -> Void = GreyBarNotice.openWallpaperSettings,
    reply: @escaping (GreyBarNoticeAnswer) -> Void
  ) {
    self.present = present
    self.openSettings = openSettings
    self.reply = reply
    super.init()
    alert.messageText = localizer(.greyBarTitle)
    alert.informativeText = localizer(.greyBarMessage, Localizer.appName)
    let open = alert.addButton(withTitle: localizer(.openWallpaperSettings))
    let later = alert.addButton(withTitle: localizer(.notNow))
    later.keyEquivalent = "\u{1b}"
    for button in [open, later] {
      button.target = self
      button.action = #selector(choose(_:))
    }
    alert.layout()
  }

  /// Shows the alert and activates the app.
  func show() {
    retained = self
    present(alert.window, true)
  }

  /// Only the first click answers; it closes the alert and releases the notice.
  @objc private func choose(_ sender: NSButton) {
    guard let reply, let index = alert.buttons.firstIndex(where: { $0 === sender }) else {
      return
    }
    self.reply = nil
    alert.window.orderOut(nil)
    let answer: GreyBarNoticeAnswer = index == 0 ? .openSettings : .notNow
    if answer == .openSettings { openSettings() }
    reply(answer)
    retained = nil
  }

  static func openWallpaperSettings() {
    let workspace = NSWorkspace.shared
    _ = GreyBarNoticeCoordinator.openWallpaperSettings(
      open: { workspace.open($0) },
      systemSettings: {
        workspace.urlForApplication(
          withBundleIdentifier: GreyBarNoticeCoordinator.systemSettingsBundleIdentifier)
      })
  }
}
