import AppKit
import TopNVCore
import XCTest

@testable import TopNV

/// The notice about the grey menu bar, presented like the first-launch question.
@MainActor
final class GreyBarNoticeWindowTests: XCTestCase {
  private var presented: [(window: NSWindow, activate: Bool)] = []
  private var answers: [GreyBarNoticeAnswer] = []
  private var openings = 0

  private func makeNotice() -> GreyBarNotice {
    GreyBarNotice(
      localizer: Localizer(bundle: .main),
      present: { [weak self] in self?.presented.append((window: $0, activate: $1)) },
      openSettings: { [weak self] in self?.openings += 1 },
      reply: { [weak self] in self?.answers.append($0) })
  }

  private func click(_ button: NSButton) {
    guard let action = button.action else { return }
    NSApplication.shared.sendAction(action, to: button.target, from: button)
  }

  func testTheNoticeExplainsTheFixWithTwoButtonsWithoutAModalSession() {
    let notice = makeNotice()
    notice.show()
    defer { click(notice.alert.buttons[1]) }
    let alert = notice.alert
    XCTAssertEqual(alert.messageText, "Finish Setting Up the Black Bar")
    XCTAssertEqual(
      alert.informativeText,
      "macOS drew the menu bar before TopNV started. Click your current wallpaper once in "
        + "Wallpaper settings and the bar turns black.")
    XCTAssertEqual(alert.buttons.map(\.title), ["Open Wallpaper Settings", "Not Now"])
    XCTAssertEqual(alert.buttons[0].keyEquivalent, "\r")
    XCTAssertEqual(alert.buttons[1].keyEquivalent, "\u{1b}")
    XCTAssertEqual(presented.count, 1)
    XCTAssertTrue(presented.first?.window === alert.window)
    XCTAssertEqual(presented.first?.activate, true)
    XCTAssertNil(NSApplication.shared.modalWindow)
    XCTAssertTrue(answers.isEmpty)
    XCTAssertEqual(openings, 0)
  }

  func testOnlyTheFirstClickAnswersAndOnlyTheFirstButtonOpensSettings() {
    for (button, answer, opened) in [(0, GreyBarNoticeAnswer.openSettings, 1), (1, .notNow, 0)] {
      answers = []
      openings = 0
      let notice = makeNotice()
      notice.show()
      let buttons = notice.alert.buttons
      click(buttons[button])
      XCTAssertEqual(answers, [answer])
      XCTAssertEqual(openings, opened)
      click(buttons[0])
      click(buttons[1])
      XCTAssertEqual(answers, [answer])
      XCTAssertEqual(openings, opened)
      XCTAssertFalse(notice.alert.window.isVisible)
    }
  }

  func testTheNoticeKeepsItselfAliveUntilTheAnswer() throws {
    weak var shown: GreyBarNotice?
    var buttons: [NSButton] = []
    do {
      let notice = makeNotice()
      notice.show()
      shown = notice
      buttons = notice.alert.buttons
    }
    XCTAssertNotNil(shown)
    click(try XCTUnwrap(buttons.last))
    XCTAssertEqual(answers, [.notNow])
    XCTAssertNil(shown)
  }
}

/// Where the app reads the appearance of the menu bar. Each test removes its items.
@MainActor
final class MenuBarConditionsMonitorTests: XCTestCase {
  private var suiteName = ""
  private var defaults: UserDefaults!
  private var items: [NSStatusItem] = []

  override func setUpWithError() throws {
    suiteName = "MenuBarConditionsMonitorTests.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
  }

  override func tearDown() {
    for item in items { NSStatusBar.system.removeStatusItem(item) }
    items = []
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
  }

  func testLightAndDarkAppearances() throws {
    let cases: [(NSAppearance.Name, MenuBarAppearance)] = [
      (.aqua, .light), (.vibrantLight, .light), (.darkAqua, .dark), (.vibrantDark, .dark),
    ]
    for (name, expected) in cases {
      let appearance = try XCTUnwrap(NSAppearance(named: name))
      XCTAssertEqual(MenuBarConditionsMonitor.appearance(of: appearance), expected, name.rawValue)
    }
  }

  func testTheMonitorReadsTheOwnItemWhenVisibleAndAZeroLengthItemOtherwise() throws {
    let own = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    items.append(own)
    let visibility = MenuVisibility(
      defaults: defaults, key: AppSettings.showMenuBarIconKey, schedule: { $0() })
    let monitor = MenuBarConditionsMonitor(
      settings: AppSettings(defaults: defaults), statusItem: own, visibility: visibility)
    monitor.start()
    defer { monitor.stop() }
    XCTAssertNil(monitor.probe)
    XCTAssertTrue(monitor.observedButton === own.button)

    visibility.setMenuVisible(false)
    monitor.followVisibility()
    let probe = try XCTUnwrap(monitor.probe)
    XCTAssertEqual(probe.length, 0)
    XCTAssertNotNil(probe.button)
    XCTAssertTrue(monitor.observedButton === probe.button)

    visibility.setMenuVisible(true)
    monitor.followVisibility()
    XCTAssertNil(monitor.probe)
    XCTAssertTrue(monitor.observedButton === own.button)
  }

  func testTheConditionsFollowTheHideNotchSetting() {
    let own = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    items.append(own)
    let settings = AppSettings(defaults: defaults)
    let monitor = MenuBarConditionsMonitor(
      settings: settings, statusItem: own,
      visibility: MenuVisibility(defaults: defaults, key: AppSettings.showMenuBarIconKey))
    XCTAssertTrue(monitor.conditions.hidesNotch)
    settings.hideNotch = false
    XCTAssertFalse(monitor.conditions.hidesNotch)
    // No band window exists in the test runner.
    XCTAssertFalse(monitor.conditions.isBandOnScreen)
  }
}
