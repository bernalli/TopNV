import AppKit
import TopNVCore

/// The question about automatic update checks at first launch, presented as in MonoPods.
///
/// Like the update driver, the alert's window is shown without a modal session, so the run loop
/// and the menu keep running. The question keeps itself alive until the first click; later clicks
/// do nothing.
@MainActor final class AutomaticUpdateQuestion: NSObject {
  let alert = NSAlert()
  private let present: @MainActor (NSWindow, Bool) -> Void
  private var reply: ((AutomaticUpdateAnswer) -> Void)?
  /// Holds the question while it waits for its answer.
  private var retained: AutomaticUpdateQuestion?
  private var closeObserver: NSObjectProtocol?

  /// The entry point of `UpdateCoordinator`.
  static func ask(_ reply: @escaping (AutomaticUpdateAnswer) -> Void) {
    AutomaticUpdateQuestion(reply: reply).show()
  }

  init(
    localizer: Localizer = .main,
    present: @escaping @MainActor (NSWindow, Bool) -> Void = AppleStyleUpdateDriver.present,
    reply: @escaping (AutomaticUpdateAnswer) -> Void
  ) {
    self.present = present
    self.reply = reply
    super.init()
    alert.messageText = localizer(.updateQuestionTitle)
    alert.informativeText = localizer(.updateQuestionMessage, Localizer.appName)
    let enable = alert.addButton(withTitle: localizer(.checkAutomatically))
    let decline = alert.addButton(withTitle: localizer(.dontCheck))
    decline.keyEquivalent = "\u{1b}"
    for button in [enable, decline] {
      button.target = self
      button.action = #selector(choose(_:))
    }
    alert.layout()
  }

  /// Shows the alert and activates the app.
  func show() {
    retained = self
    if closeObserver == nil {
      closeObserver = NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification, object: alert.window, queue: nil
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.finish(.dismissed) }
      }
    }
    present(alert.window, true)
  }

  /// The first button enables, the second declines; anything else dismisses.
  static func answer(buttonIndex: Int?) -> AutomaticUpdateAnswer {
    switch buttonIndex {
    case 0: return .enable
    case 1: return .decline
    default: return .dismissed
    }
  }

  /// Only the first click answers; it closes the alert and releases the question.
  @objc private func choose(_ sender: NSButton) {
    guard let index = alert.buttons.firstIndex(where: { $0 === sender }) else {
      return
    }
    finish(Self.answer(buttonIndex: index))
  }

  private func finish(_ answer: AutomaticUpdateAnswer) {
    if let closeObserver {
      NotificationCenter.default.removeObserver(closeObserver)
      self.closeObserver = nil
    }
    guard let reply else { return }
    self.reply = nil
    alert.window.orderOut(nil)
    reply(answer)
    retained = nil
  }
}
