import AppKit
import SwiftUI
import TopNVCore

@MainActor
final class AboutWindowController: NSWindowController {
  static let shared = AboutWindowController()

  private init() {
    let information = AboutInformation(infoDictionary: Bundle.main.infoDictionary)
    let content = NSHostingView(rootView: AboutView(information: information))
    let window = AboutWindow(
      contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = Localizer.main(.about, information.name)
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.backgroundColor = .windowBackgroundColor
    window.isReleasedWhenClosed = false
    window.contentView = content
    window.setContentSize(content.fittingSize)
    window.initialFirstResponder = content
    window.center()
    super.init(window: window)
  }

  required init?(coder: NSCoder) { nil }

  func show() {
    // The default run-loop mode resumes after the native menu finishes tracking.
    RunLoop.main.perform(inModes: [.default]) { [self] in
      MainActor.assumeIsolated {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil)
      }
    }
  }
}

private final class AboutWindow: NSWindow {
  override func cancelOperation(_ sender: Any?) {
    performClose(sender)
  }
}
