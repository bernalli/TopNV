import AppKit
import TopNVCore

@MainActor
enum AutomaticUpdateQuestion {
  static func ask(_ completion: @escaping (AutomaticUpdateAnswer) -> Void) {
    RunLoop.main.perform(inModes: [.default]) {
      MainActor.assumeIsolated {
        let alert = NSAlert()
        alert.messageText = "Check for Updates Automatically?"
        alert.informativeText = "TopNV can check for new versions once a day. Installing requires Install Update, then Install and Relaunch. You can change this at any time in Options."
        alert.addButton(withTitle: "Check Automatically")
        alert.addButton(withTitle: "Don't Check").keyEquivalent = "\u{1b}"
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
