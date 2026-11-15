import AppKit
import SwiftUI
import TopNVCore

/// Closes on Escape and Command-W, which an accessory app without a File menu does not get.
final class AboutWindow: NSWindow {
  override func cancelOperation(_ sender: Any?) {
    close()
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.type == .keyDown,
      event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
      event.charactersIgnoringModifiers?.lowercased() == "w"
    {
      close()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

/// Owns the single About window, as in MonoPods. Links and activation are injected, so tests never
/// open a browser. The window reads no table: it is English in every language (D-35).
@MainActor final class AboutWindowController {
  static let shared = AboutWindowController()

  private let information: AboutInformation
  private let titleFontURL: URL?
  private let gitHubMarkURL: URL?
  private let open: @MainActor (URL) -> Void
  private let activate: @MainActor () -> Void
  private var existing: AboutWindow?

  /// `bundle` supplies the artwork and, without `infoDictionary`, the name and version.
  init(
    bundle: Bundle = .main, infoDictionary: [String: Any]? = nil, titleFontURL: URL? = nil,
    gitHubMarkURL: URL? = nil,
    open: @escaping @MainActor (URL) -> Void = { _ = NSWorkspace.shared.open($0) },
    activate: @escaping @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) }
  ) {
    information = AboutInformation(
      infoDictionary: infoDictionary ?? bundle.infoDictionary, localizer: AboutText.localizer)
    self.titleFontURL =
      titleFontURL ?? bundle.url(forResource: "PlusJakartaSans-SemiBold", withExtension: "ttf")
    self.gitHubMarkURL = gitHubMarkURL ?? bundle.url(forResource: "GitHubMark", withExtension: "pdf")
    self.open = open
    self.activate = activate
  }

  /// Brings the About window to the front, creating it on first use. The app is an accessory app,
  /// so it is activated first or the window would open behind the frontmost app.
  func show() {
    activate()
    window.makeKeyAndOrderFront(nil)
  }

  /// The one About window, built and centred the first time it is needed and kept after closing.
  var window: NSWindow {
    if let existing { return existing }
    let view = AboutView(
      information: information, icon: NSApplication.shared.applicationIconImage,
      gitHubMark: AboutArtwork.templateImage(contentsOf: gitHubMarkURL),
      titleFont: AboutTitleFont.load(contentsOf: titleFontURL),
      openRepository: { [weak self] in self?.openLink(.source) },
      openSponsors: { [weak self] in self?.openLink(.sponsor) })
    let hosting = NSHostingView(rootView: view)
    let window = AboutWindow(
      contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
      styleMask: [.titled, .closable], backing: .buffered, defer: true)
    window.title = AboutText.windowTitle
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.contentView = hosting
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
    window.center()
    existing = window
    return window
  }

  private func openLink(_ link: AppLink) {
    guard let url = link.url else { return }
    open(url)
  }
}
