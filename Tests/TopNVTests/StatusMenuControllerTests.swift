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

  private struct Fixture {
    let controller: StatusMenuController
    let visibility: MenuVisibility
    let settings: AppSettings
  }

  private func makeController(updates: UpdateMenuModel? = nil, isTestCopy: Bool = false,
                              relativeKey: RelativeMenuBarKey? = nil) -> Fixture {
    let settings = AppSettings(defaults: defaults)
    let visibility = MenuVisibility(
      defaults: defaults, key: AppSettings.showMenuBarIconKey, schedule: { $0() })
    let controller = StatusMenuController(
      settings: settings, loginItem: LoginItem(), updates: updates ?? UpdateMenuModel(updater: nil),
      visibility: visibility, isTestCopy: isTestCopy, relativeKey: relativeKey)
    self.controller = controller
    return Fixture(controller: controller, visibility: visibility, settings: settings)
  }

  /// The production menu has no animation preview, and a preview command that reaches it does nothing.
  func testOnlyATestCopyHasAndPerformsTheAnimationPreview() {
    var previews = 0

    let production = makeController()
    production.controller.onEntrancePreview = { previews += 1 }
    XCTAssertTrue(production.settings.hideNotch)
    XCTAssertFalse(production.controller.menu.items.contains { $0.title == "Animation preview" })
    production.controller.perform(.previewCalm)
    XCTAssertEqual(previews, 0)
    NSStatusBar.system.removeStatusItem(production.controller.statusItem)

    let testCopy = makeController(isTestCopy: true)
    testCopy.controller.onEntrancePreview = { previews += 1 }
    XCTAssertTrue(testCopy.controller.menu.items.contains { $0.title == "Animation preview" })
    testCopy.controller.perform(.previewCalm)
    XCTAssertEqual(previews, 1)
    testCopy.controller.perform(.previewCalm)
    XCTAssertEqual(previews, 2)
    testCopy.settings.hideNotch = false
    testCopy.controller.perform(.previewCalm)
    XCTAssertEqual(previews, 2)
  }

  func testOnlyTheTestMenuOffersTheLampNextToTheRelativeKey() throws {
    let production = makeController().controller
    var changes = 0
    production.onLampChanged = { changes += 1 }
    XCTAssertNil(production.menu.item(withTitle: "Lamp under key (test)"))
    production.perform(.lampUnderKey)
    XCTAssertEqual(changes, 0)
    NSStatusBar.system.removeStatusItem(production.statusItem)

    let key = RelativeMenuBarKey(isTestCopy: true)
    let testCopy = makeController(isTestCopy: true, relativeKey: key).controller
    testCopy.onLampChanged = { changes += 1 }
    let titles = testCopy.menu.items.map(\.title)
    let index = try XCTUnwrap(titles.firstIndex(of: "Relative key (test)"))
    XCTAssertEqual(titles.dropFirst(index + 1).first, "Lamp under key (test)")
    let lamp = try XCTUnwrap(testCopy.menu.item(withTitle: "Lamp under key (test)"))
    XCTAssertEqual(lamp.state, .off)
    testCopy.perform(.lampUnderKey)
    XCTAssertTrue(key.lampEnabled)
    XCTAssertFalse(key.enabled)
    XCTAssertEqual(lamp.state, .on)
    testCopy.perform(.lampUnderKey)
    XCTAssertFalse(key.lampEnabled)
    XCTAssertEqual(lamp.state, .off)
    XCTAssertEqual(changes, 2)
  }

  func testLampMenuModesAreExclusiveAndTestCopyOnly() throws {
    let production = makeController().controller
    XCTAssertNil(production.menu.item(withTitle: "Lamp only (test)"))
    production.perform(.lampOnly)
    NSStatusBar.system.removeStatusItem(production.statusItem)

    let menu = makeController(isTestCopy: true, relativeKey: RelativeMenuBarKey(isTestCopy: true)).controller
    let only = try XCTUnwrap(menu.menu.item(withTitle: "Lamp only (test)"))
    let under = try XCTUnwrap(menu.menu.item(withTitle: "Lamp under key (test)"))
    XCTAssertEqual([only.state, under.state], [.off, .off])
    for (command, states): (MenuCommand, [NSControl.StateValue]) in [
      (.lampOnly, [.on, .off]), (.lampUnderKey, [.off, .on]), (.lampOnly, [.on, .off]), (.lampOnly, [.off, .off])
    ] {
      menu.perform(command)
      XCTAssertEqual([only.state, under.state], states)
    }
  }

  func testTheStatusItemCanBeRemovedByTheUserAndShowsTheMenu() {
    let controller = makeController().controller
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
    let fixture = makeController()
    let controller = fixture.controller
    let visibility = fixture.visibility
    XCTAssertTrue(controller.statusItem.isVisible)

    controller.statusItem.isVisible = false

    XCTAssertFalse(visibility.isVisible)
    XCTAssertEqual(defaults.object(forKey: AppSettings.showMenuBarIconKey) as? Bool, false)
  }

  /// Reopening the app turns the setting back on, and the next refresh shows the icon.
  func testReopeningShowsTheIconAgain() {
    let fixture = makeController()
    let controller = fixture.controller
    let visibility = fixture.visibility
    controller.statusItem.isVisible = false
    XCTAssertFalse(visibility.isVisible)

    visibility.setMenuVisible(true)
    controller.refresh()

    XCTAssertTrue(controller.statusItem.isVisible)
    XCTAssertEqual(defaults.object(forKey: AppSettings.showMenuBarIconKey) as? Bool, true)
  }

  /// Hide Menu Bar Icon is a command: it hides the icon and never shows it again.
  func testTheHideCommandOnlyHidesTheIcon() throws {
    let fixture = makeController()
    let controller = fixture.controller
    let visibility = fixture.visibility
    let options = try XCTUnwrap(controller.menu.items.first { $0.title == "Options" }?.submenu)
    let hide = try XCTUnwrap(options.items.first { $0.title == "Hide Menu Bar Icon" })
    XCTAssertEqual(hide.state, .off)
    controller.perform(.hideMenuBarIcon)
    controller.refresh()
    XCTAssertFalse(visibility.isVisible)
    XCTAssertFalse(controller.statusItem.isVisible)
    controller.perform(.hideMenuBarIcon)
    controller.refresh()
    XCTAssertFalse(visibility.isVisible)
    XCTAssertEqual(hide.state, .off)
  }

  func testSwitchCommandsChangeTheSettings() {
    let fixture = makeController()
    let controller = fixture.controller
    let settings = fixture.settings
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
    let fixture = makeController()
    let controller = fixture.controller
    let settings = fixture.settings
    let toggle = try XCTUnwrap(controller.menu.items.first { $0.title == "Hide Notch" })
    XCTAssertEqual(toggle.state, .on)
    settings.hideNotch = false
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    XCTAssertEqual(toggle.state, .off)
    XCTAssertTrue(controller.menu.items.first { $0.title == "Hide Notch" } === toggle)
  }

  /// Without an updater, MonoPods shows no update items.
  func testNoUpdateItemsWithoutAnUpdater() {
    let controller = makeController().controller
    XCTAssertFalse(controller.menu.items.contains { $0.title == "Check for Updates…" })
  }

  /// Before the first-launch answer the update items are shown and dimmed.
  func testUpdateItemsAreDimmedUntilTheUpdaterStarts() throws {
    let updates = UpdateMenuModel(updater: StartableUpdater(), schedule: { $0() })
    let controller = makeController(updates: updates).controller
    let check = try XCTUnwrap(controller.menu.items.first { $0.title == "Check for Updates…" })
    let options = try XCTUnwrap(controller.menu.items.first { $0.title == "Options" }?.submenu)
    let automatic = try XCTUnwrap(
      options.items.first { $0.title == "Check for Updates Automatically" })
    XCTAssertFalse(check.isEnabled)
    XCTAssertFalse(automatic.isEnabled)
    XCTAssertEqual(automatic.state, .off)
    updates.updaterDidStart()
    controller.refresh()
    XCTAssertTrue(check.isEnabled)
    XCTAssertTrue(automatic.isEnabled)
  }

  /// An updater that cannot start leaves no update items.
  func testAFailedUpdaterHidesTheUpdateItems() throws {
    let updates = UpdateMenuModel(updater: StartableUpdater(), schedule: { $0() })
    let controller = makeController(updates: updates).controller
    XCTAssertTrue(controller.menu.items.contains { $0.title == "Check for Updates…" })
    updates.updaterDidFail()
    controller.refresh()
    XCTAssertFalse(controller.menu.items.contains { $0.title == "Check for Updates…" })
    let options = try XCTUnwrap(controller.menu.items.first { $0.title == "Options" }?.submenu)
    XCTAssertFalse(options.items.contains { $0.title == "Check for Updates Automatically" })
  }
}

@MainActor private final class StartableUpdater: UpdaterControlling {
  var canCheckForUpdates = true
  var automaticallyChecksForUpdates = false
  func start() throws {}
  func checkForUpdates() {}
}
