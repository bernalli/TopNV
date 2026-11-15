import AppKit
import TopNVCore
import XCTest

@testable import TopNV

/// The app has no SwiftUI scene: this menu is its whole main menu, as in MonoPods.
@MainActor
final class ApplicationMenuTests: XCTestCase {
  func testTheMainMenuHoldsOnlyQuitWithCommandQ() throws {
    var quits = 0
    let menu = ApplicationMenu.make(localizer: Localizer(bundle: .main)) { quits += 1 }

    XCTAssertEqual(menu.items.count, 1)
    let applicationMenu = try XCTUnwrap(menu.items.first?.submenu)
    XCTAssertEqual(applicationMenu.items.count, 1)
    let quit = try XCTUnwrap(applicationMenu.items.first)
    XCTAssertEqual(quit.title, "Quit TopNV")
    XCTAssertEqual(quit.keyEquivalent, "q")
    XCTAssertEqual(quit.keyEquivalentModifierMask, .command)
    XCTAssertTrue(quit.isEnabled)
    let settings = NSSelectorFromString("showSettingsWindow:")
    for item in menu.items + applicationMenu.items {
      XCTAssertNotEqual(item.action, settings)
      XCTAssertFalse(item.title.localizedCaseInsensitiveContains("Settings"))
    }
    // Items hold their target weakly: the item keeps its own action alive.
    let target = try XCTUnwrap(quit.target as? NSObject)
    _ = target.perform(try XCTUnwrap(quit.action), with: quit)
    XCTAssertEqual(quits, 1)
  }
}
