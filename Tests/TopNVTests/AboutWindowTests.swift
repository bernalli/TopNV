import AppKit
import CoreText
import CryptoKit
import SwiftUI
import TopNVCore
import XCTest

@testable import TopNV

/// The About window as MonoPods builds it. Links and activation are injected, so no test opens a
/// browser or activates the app.
@MainActor
final class AboutWindowTests: XCTestCase {
  private static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  private static let assets = repository.appendingPathComponent("Assets")
  private static let wordmark = assets.appendingPathComponent("Fonts/PlusJakartaSans-SemiBold.ttf")
  private static let gitHubMark = assets.appendingPathComponent("GitHubMark.pdf")
  private static let italian = repository.appendingPathComponent("Localization/it.lproj")

  private var opened: [URL] = []
  private var activations = 0

  private func controller(
    bundle: Bundle = .main,
    infoDictionary: [String: Any]? = ["CFBundleShortVersionString": "1.2.0"],
    titleFontURL: URL? = AboutWindowTests.wordmark,
    gitHubMarkURL: URL? = AboutWindowTests.gitHubMark
  ) -> AboutWindowController {
    AboutWindowController(
      bundle: bundle, infoDictionary: infoDictionary, titleFontURL: titleFontURL,
      gitHubMarkURL: gitHubMarkURL, open: { [weak self] in self?.opened.append($0) },
      activate: { [weak self] in self?.activations += 1 })
  }

  private func view(of controller: AboutWindowController) throws -> AboutView {
    try XCTUnwrap(controller.window.contentView as? NSHostingView<AboutView>).rootView
  }

  // MARK: Window

  func testTheWindowIsASingleTitledWindowWithOnlyTheCloseButton() {
    let controller = controller()
    let window = controller.window
    XCTAssertTrue(controller.window === window)
    XCTAssertTrue(window is AboutWindow)
    XCTAssertEqual(window.styleMask, [.titled, .closable])
    XCTAssertEqual(window.titleVisibility, .hidden)
    XCTAssertFalse(window.titlebarAppearsTransparent)
    XCTAssertNil(window.initialFirstResponder)
    XCTAssertEqual(window.standardWindowButton(.closeButton)?.isHidden, false)
    XCTAssertTrue(window.standardWindowButton(.miniaturizeButton)?.isHidden ?? true)
    XCTAssertTrue(window.standardWindowButton(.zoomButton)?.isHidden ?? true)
    XCTAssertFalse(window.isReleasedWhenClosed)
    XCTAssertFalse(window.isVisible)
    XCTAssertTrue(window.contentView is NSHostingView<AboutView>)
  }

  func testShowActivatesTheAppAndLinksOpenThroughTheInjectedOpener() throws {
    let controller = controller()
    controller.show()
    XCTAssertEqual(activations, 1)
    XCTAssertTrue(controller.window.isVisible)
    controller.window.close()
    let view = try view(of: controller)
    view.openRepository()
    view.openSponsors()
    XCTAssertEqual(opened, [AppLink.source.url, AppLink.sponsor.url].compactMap { $0 })
  }

  /// Counts close notifications posted while `action` runs; closing posts it synchronously.
  private func closes(_ window: NSWindow, after action: () -> Void) -> Bool {
    let count = CloseCount()
    let token = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: nil
    ) { _ in count.add() }
    action()
    NotificationCenter.default.removeObserver(token)
    return count.value > 0
  }

  private func key(_ characters: String, _ modifiers: NSEvent.ModifierFlags) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
      context: nil, characters: characters, charactersIgnoringModifiers: characters,
      isARepeat: false, keyCode: 0)
  }

  func testEscapeClosesTheWindowAndKeepsItForReuse() {
    let controller = controller()
    let window = controller.window
    XCTAssertTrue(closes(window) { window.cancelOperation(nil) })
    XCTAssertTrue(controller.window === window)
  }

  // Closing a window that is already closed posts no notification, so each case uses a new window.
  func testCommandWClosesTheWindow() throws {
    for flags: NSEvent.ModifierFlags in [.command, [.command, .capsLock]] {
      let window = controller().window
      let commandW = try XCTUnwrap(key("w", flags))
      var handled = false
      XCTAssertTrue(closes(window) { handled = window.performKeyEquivalent(with: commandW) })
      XCTAssertTrue(handled)
    }
  }

  func testOtherKeysDoNotCloseTheWindow() {
    let window = controller().window
    let others = [key("w", [.command, .shift]), key("w", []), key("q", .command)].compactMap { $0 }
    XCTAssertEqual(others.count, 3)
    for event in others {
      XCTAssertFalse(closes(window) { _ = window.performKeyEquivalent(with: event) })
    }
  }

  // MARK: English in every language (D-35)

  /// The About window reads no table: with the Italian table as its bundle it stays in English.
  func testTheWindowStaysInEnglishWithTheItalianTable() throws {
    let italian = try XCTUnwrap(Bundle(path: Self.italian.path))
    XCTAssertEqual(Localizer(bundle: italian)(.about, "TopNV"), "Informazioni su TopNV")
    let controller = controller(
      bundle: italian,
      infoDictionary: [
        "CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "7",
        "NSHumanReadableCopyright": "Copyright (c) 2026 Example",
      ])
    XCTAssertEqual(controller.window.title, "About TopNV")
    let view = try view(of: controller)
    XCTAssertEqual(view.information.version.title, "Version 1.2.0 (7)")
    XCTAssertEqual(view.information.copyright, "Copyright (c) 2026 Example")
    XCTAssertEqual(AboutText.gitHubHelp, "View TopNV on GitHub")
    XCTAssertEqual(AboutText.sponsor, "Buy Me a Coffee")
    XCTAssertEqual(
      self.controller(bundle: italian, infoDictionary: nil).window.title, "About TopNV")
    XCTAssertEqual(
      try self.view(of: self.controller(bundle: italian, infoDictionary: nil))
        .information.version.title,
      "Version Unavailable")
  }

  // MARK: Title font (D-33)

  func testTheNameUsesPlusJakartaSansSemiBold() throws {
    let font = try view(of: controller()).titleFont
    XCTAssertEqual(font.fontName, "PlusJakartaSans-SemiBold")
    XCTAssertEqual(font.pointSize, NSFont.systemFontSize + 1)
    XCTAssertEqual(
      AboutTitleFont.load(contentsOf: Self.wordmark).fontName, "PlusJakartaSans-SemiBold")
  }

  func testTheNameFallsBackToTheBoldSystemFont() throws {
    let fallback = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize + 1)
    _ = AboutTitleFont.load(contentsOf: Self.wordmark)
    XCTAssertEqual(AboutTitleFont.load(contentsOf: nil), fallback)
    for url in [Self.gitHubMark, Self.assets.appendingPathComponent("none.ttf")] {
      XCTAssertEqual(AboutTitleFont.load(contentsOf: url), fallback, url.lastPathComponent)
    }
    XCTAssertEqual(try view(of: controller(titleFontURL: nil)).titleFont, fallback)
  }

  // MARK: GitHub mark

  func testTheBundledGitHubMarkIsTheUnmodifiedOfficialAsset() throws {
    // SHA-256 of GitHub_Invertocat_Black.pdf from the GitHub logo kit, the file MonoPods ships.
    let digest = SHA256.hash(data: try Data(contentsOf: Self.gitHubMark))
    XCTAssertEqual(
      digest.map { String(format: "%02x", $0) }.joined(),
      "9d30aac7deaf046f3e6ca4a46a6d03bcc347c595c64521dc103f4bad313aaf65")
  }

  func testTheGitHubMarkIsAVectorTemplateImage() throws {
    let mark = try XCTUnwrap(try view(of: controller()).gitHubMark)
    XCTAssertTrue(mark.isTemplate)
    XCTAssertTrue(mark.representations.contains { $0 is NSPDFImageRep })
  }

  /// Without the asset there is no button, as in MonoPods: no fallback symbol.
  func testWithoutTheAssetThereIsNoGitHubButton() throws {
    XCTAssertNil(try view(of: controller(gitHubMarkURL: nil)).gitHubMark)
    XCTAssertNil(
      try view(of: controller(gitHubMarkURL: Self.assets.appendingPathComponent("none.pdf")))
        .gitHubMark)
  }
}

private final class CloseCount: @unchecked Sendable {
  // Only touched on the main thread: close() posts the notification synchronously.
  private(set) var value = 0
  func add() { value += 1 }
}
