import AppKit
import TopNVCore

@MainActor
enum AutomaticUpdateQuestion {
  static func ask(_ completion: @escaping (AutomaticUpdateAnswer) -> Void) {
    RunLoop.main.perform(inModes: [.default]) {
      MainActor.assumeIsolated {
        let alert = NSAlert()
        let localizer = Localizer.main
        alert.messageText = localizer(.updateQuestionTitle)
        alert.informativeText = localizer(.updateQuestionMessage, Localizer.appName)
        alert.addButton(withTitle: localizer(.checkAutomatically))
        alert.addButton(withTitle: localizer(.dontCheck)).keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        completion(answer(for: alert.runModal()))
      }
    }
  }
  static func answer(for response: NSApplication.ModalResponse) -> AutomaticUpdateAnswer {
    switch response {
    case .alertFirstButtonReturn: return .enable
    case .alertSecondButtonReturn: return .decline
    default: return .dismissed
    }
  }
}
