import AppKit
import CoreText
import CryptoKit
import SwiftUI
import XCTest

@testable import TopNV
@testable import TopNVCore

/// The About window as MonoPods builds it. Links and activation are injected, so no test opens a
/// browser or activates the app.
@MainActor
final class AboutWindowTests: XCTestCase {
  nonisolated private static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  nonisolated private static let assets = repository.appendingPathComponent("Assets")
  nonisolated private static let wordmark = assets.appendingPathComponent(
    "Fonts/PlusJakartaSans-SemiBold.ttf")
  nonisolated private static let gitHubMark = assets.appendingPathComponent("GitHubMark.pdf")
  nonisolated private static let italian = repository.appendingPathComponent(
    "Localization/it.lproj")

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

  // MARK: English in every language

  /// Checks About data and window title while Localizer.main uses the Italian table.
  func testTheWindowStaysInEnglishWithTheItalianTable() throws {
    let italian = try XCTUnwrap(Bundle(path: Self.italian.path))
    // This override affects Localizer.main only, not Foundation or SwiftUI localization.
    // scripts/tests/test-about-english.sh guards changes to the reviewed About source path.
    try Localizer.$bundleOverride.withValue(italian) {
      try checkTheWindowInEnglish(italian: italian)
    }
  }

  private func checkTheWindowInEnglish(italian: Bundle) throws {
    XCTAssertEqual(Localizer.main(.options), "Opzioni")
    XCTAssertEqual(Localizer.main(.about, "TopNV"), "Informazioni su TopNV")
    XCTAssertEqual(
      AboutInformation(infoDictionary: [
        "CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "7",
      ]).version.title,
      "Version 1.2.0")
    XCTAssertEqual(Localizer(bundle: italian)(.about, "TopNV"), "Informazioni su TopNV")
    let controller = controller(
      bundle: italian,
      infoDictionary: [
        "CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "7",
        "NSHumanReadableCopyright": "Copyright (c) 2026 Example",
      ])
    XCTAssertEqual(controller.window.title, "About TopNV")
    let view = try view(of: controller)
    XCTAssertEqual(view.information.version.title, "Version 1.2.0")
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

  // MARK: Title font

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

  // MARK: Sponsor button

  nonisolated private static let coffeeStyle = repository.appendingPathComponent(
    "Sources/TopNV/CoffeeButtonStyle.swift")

  /// The style is MonoPods' CoffeeButtonStyle.swift at d5517ff, copied byte for byte.
  func testTheCoffeeStyleIsTheUnmodifiedMonoPodsFile() throws {
    let digest = SHA256.hash(data: try Data(contentsOf: Self.coffeeStyle))
    XCTAssertEqual(
      digest.map { String(format: "%02x", $0) }.joined(),
      "be5c7fe2991986468abadd9ac1696b4d10be8200c4e4e504ed74997d3c67a741")
  }

  /// The sponsor button is written as in MonoPods' AboutWindow.swift at d5517ff.
  func testTheSponsorButtonUsesTheCapsuleStyle() throws {
    let source = try String(
      contentsOf: Self.repository.appendingPathComponent("Sources/TopNV/AboutView.swift"),
      encoding: .utf8)
    let start = try XCTUnwrap(source.range(of: "Button(action: openSponsors)"))
    let end = try XCTUnwrap(
      source.range(of: ".padding(.top, 14)", range: start.upperBound..<source.endIndex))
    let button = String(source[start.lowerBound..<end.lowerBound])
    XCTAssertTrue(
      button.contains(#"Label(AboutText.sponsor, systemImage: "cup.and.saucer.fill")"#), button)
    XCTAssertTrue(button.contains(".buttonStyle(CoffeeButtonStyle())"), button)
    XCTAssertTrue(button.contains(".focusEffectDisabled()"), button)
    XCTAssertFalse(button.contains(".controlSize("), button)
  }

  /// A capsule leaves the corners of its frame empty and draws a faint primary-colour fill.
  func testTheCoffeeButtonIsDrawnAsALowContrastCapsule() throws {
    let button = Button {
    } label: {
      Label(AboutText.sponsor, systemImage: "cup.and.saucer.fill")
    }
    .buttonStyle(CoffeeButtonStyle())
    for name in [NSAppearance.Name.aqua, .darkAqua] {
      let appearance = try XCTUnwrap(NSAppearance(named: name))
      let hosting = NSHostingView(rootView: button)
      hosting.appearance = appearance
      hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
      hosting.layoutSubtreeIfNeeded()
      let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
      appearance.performAsCurrentDrawingAppearance {
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
      }
      let width = bitmap.pixelsWide
      let height = bitmap.pixelsHigh
      let scale = CGFloat(width) / bitmap.size.width
      XCTAssertTrue(width > height && height > 0, name.rawValue)
      func alpha(_ column: Int, _ row: Int) -> CGFloat {
        bitmap.colorAt(x: column, y: row)?.alphaComponent ?? -1
      }
      for (column, row) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)] {
        XCTAssertEqual(alpha(column, row), 0, "\(name.rawValue) corner \(column),\(row)")
      }
      XCTAssertGreaterThan(alpha(0, height / 2), 0, "\(name.rawValue) left edge")
      XCTAssertGreaterThan(alpha(width - 1, height / 2), 0, "\(name.rawValue) right edge")
      let inside = Int((4 * scale).rounded())
      let fill = try XCTUnwrap(bitmap.colorAt(x: inside, y: height / 2)?.usingColorSpace(.sRGB))
      XCTAssertTrue(
        fill.alphaComponent >= 0.02 && fill.alphaComponent <= 0.08, "\(name.rawValue) fill")
      if name == .aqua {
        XCTAssertLessThan(fill.brightnessComponent, 0.5, "light fill")
      } else {
        XCTAssertGreaterThan(fill.brightnessComponent, 0.5, "dark fill")
      }
    }
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
