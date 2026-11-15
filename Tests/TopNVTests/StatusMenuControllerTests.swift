import AppKit
import TopNVCore
import XCTest

@testable import TopNV

/// The status item and its menu, as MonoPods builds them. Each test removes its item.
@MainActor
final class StatusMenuControllerTests: XCTestCase {
  private var suiteName = ""
  private var defaults: UserDefaults!
  private var controller: StatusMenuController?

  override func setUpWithError() throws {
    suiteName = "StatusMenuControllerTests.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
  }

  override func tearDown() {
    if let item = controller?.statusItem { NSStatusBar.system.removeStatusItem(item) }
    controller = nil
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
  }

  private func makeController() -> (StatusMenuController, MenuVisibility, AppSettings) {
    let settings = AppSettings(defaults: defaults)
    let visibility = MenuVisibility(
      defaults: defaults, key: AppSettings.showMenuBarIconKey, schedule: { $0() })
    let controller = StatusMenuController(
      settings: settings, loginItem: LoginItem(), updates: UpdateMenuModel(updater: nil),
      visibility: visibility, version: "Version 1.2.0 (7)")
    self.controller = controller
    return (controller, visibility, settings)
  }

  func testTheStatusItemCanBeRemovedByTheUserAndShowsTheMenu() {
    let (controller, _, _) = makeController()
    XCTAssertEqual(controller.statusItem.behavior, .removalAllowed)
    XCTAssertTrue(controller.statusItem.menu === controller.menu)
    XCTAssertEqual(controller.statusItem.button?.accessibilityTitle(), "TopNV")
    XCTAssertNotNil(controller.statusItem.button?.image)
    XCTAssertTrue(controller.statusItem.button?.image?.isTemplate ?? false)
    XCTAssertEqual(controller.menu.items.first?.title, "TopNV")
    XCTAssertTrue(controller.menu.items.first?.isSectionHeader ?? false)
    XCTAssertEqual(controller.menu.items.last?.title, "Quit TopNV")
  }

  /// Command-dragging the icon out of the menu bar is saved like the Hide Menu Bar Icon switch.
  func testRemovingTheIconSavesTheHiddenSetting() {
    let (controller, visibility, _) = makeController()
    XCTAssertTrue(controller.statusItem.isVisible)

    controller.statusItem.isVisible = false

    XCTAssertFalse(visibility.isVisible)
    XCTAssertEqual(defaults.object(forKey: AppSettings.showMenuBarIconKey) as? Bool, false)
  }

  /// Reopening the app turns the setting back on, and the next refresh shows the icon.
  func testReopeningShowsTheIconAgain() {
    let (controller, visibility, _) = makeController()
    controller.statusItem.isVisible = false
    XCTAssertFalse(visibility.isVisible)

    visibility.setMenuVisible(true)
    controller.refresh()

    XCTAssertTrue(controller.statusItem.isVisible)
    XCTAssertEqual(defaults.object(forKey: AppSettings.showMenuBarIconKey) as? Bool, true)
  }

  func testTheHideSwitchHidesTheIcon() {
    let (controller, visibility, _) = makeController()
    controller.perform(.hideMenuBarIcon)
    controller.refresh()
    XCTAssertFalse(visibility.isVisible)
    XCTAssertFalse(controller.statusItem.isVisible)
  }

  func testSwitchCommandsChangeTheSettings() {
    let (controller, _, settings) = makeController()
    XCTAssertTrue(settings.hideNotch)
    controller.perform(.hideNotch)
    XCTAssertFalse(settings.hideNotch)
    controller.perform(.roundCorners)
    XCTAssertFalse(settings.roundCorners)
    controller.perform(.cornersOnAllDisplays)
    XCTAssertTrue(settings.cornersOnAllDisplays)
  }

  /// A change made while the menu is open reaches its items on the next turn of the run loop.
  func testASettingChangeRefreshesTheMenu() throws {
    let (controller, _, settings) = makeController()
    let toggle = try XCTUnwrap(controller.menu.items.first { $0.title == "Hide Notch" })
    XCTAssertEqual(toggle.state, .on)
    settings.hideNotch = false
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    XCTAssertEqual(toggle.state, .off)
    XCTAssertTrue(controller.menu.items.first { $0.title == "Hide Notch" } === toggle)
  }

  /// Without an updater, MonoPods shows no update items.
  func testNoUpdateItemsWithoutAnUpdater() {
    let (controller, _, _) = makeController()
    XCTAssertFalse(controller.menu.items.contains { $0.title == "Check for Updates…" })
  }
}
