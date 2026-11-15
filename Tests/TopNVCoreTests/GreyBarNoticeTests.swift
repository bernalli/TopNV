import XCTest

@testable import TopNVCore

/// A menu bar and band whose state the test sets by hand.
@MainActor
final class FakeMenuBarSource: MenuBarConditionsSource {
  var onChange: (@MainActor () -> Void)?
  var conditions = MenuBarConditions(
    appearance: .dark, hidesNotch: true, hasNotch: true, isBandOnScreen: true)

  /// Changes the state and reports it, as the app source does after a change.
  func set(_ change: (inout MenuBarConditions) -> Void) {
    change(&conditions)
    onChange?()
  }
}

/// A clock that moves only when the test advances it.
@MainActor
final class FakeClock {
  private struct Timer {
    let id: Int
    let deadline: Duration
    let action: @MainActor () -> Void
  }

  private(set) var now: Duration = .zero
  private var timers: [Timer] = []
  private var nextID = 0

  var pendingCount: Int { timers.count }

  func schedule(_ delay: Duration, _ action: @escaping @MainActor () -> Void) -> () -> Void {
    nextID += 1
    let id = nextID
    timers.append(Timer(id: id, deadline: now + delay, action: action))
    return { [weak self] in self?.timers.removeAll { $0.id == id } }
  }

  func advance(by interval: Duration) {
    now += interval
    while let index = timers.indices.filter({ timers[$0].deadline <= now })
      .min(by: { timers[$0].deadline < timers[$1].deadline })
    {
      let timer = timers.remove(at: index)
      timer.action()
    }
  }
}

@MainActor
final class GreyBarNoticeTests: XCTestCase {
  private var source = FakeMenuBarSource()
  private var clock = FakeClock()
  private var questionOnScreen = false
  private var shown: [(GreyBarNoticeAnswer) -> Void] = []
  private var coordinator: GreyBarNoticeCoordinator?

  override func setUp() {
    source = FakeMenuBarSource()
    clock = FakeClock()
    questionOnScreen = false
    shown = []
    let clock = clock
    let coordinator = GreyBarNoticeCoordinator(
      source: source, schedule: { clock.schedule($0, $1) },
      isQuestionOnScreen: { [weak self] in self?.questionOnScreen ?? false },
      show: { [weak self] in self?.shown.append($0) })
    coordinator.start()
    self.coordinator = coordinator
  }

  private func turnLight() { source.set { $0.appearance = .light } }
  private func turnDark() { source.set { $0.appearance = .dark } }

  func testALightBarWithEveryConditionShowsTheNoticeOnceAfterTwoSeconds() {
    turnLight()
    clock.advance(by: .milliseconds(1999))
    XCTAssertEqual(shown.count, 0)
    clock.advance(by: .milliseconds(1))
    XCTAssertEqual(shown.count, 1)
    clock.advance(by: .seconds(10))
    XCTAssertEqual(shown.count, 1)
  }

  func testTheDelayIsTwoSeconds() {
    XCTAssertEqual(GreyBarNoticeCoordinator.delay, .seconds(2))
  }

  func testALightBarAtStartCountsLikeALightEvent() {
    let source = FakeMenuBarSource()
    source.conditions.appearance = .light
    var count = 0
    let coordinator = GreyBarNoticeCoordinator(
      source: source, schedule: { [clock] in clock.schedule($0, $1) },
      isQuestionOnScreen: { false }, show: { _ in count += 1 })
    coordinator.start()
    clock.advance(by: .seconds(2))
    XCTAssertEqual(count, 1)
  }

  func testADarkBarShowsNothing() {
    turnDark()
    clock.advance(by: .seconds(10))
    XCTAssertEqual(shown.count, 0)
    XCTAssertEqual(clock.pendingCount, 0)
  }

  func testAnUnknownAppearanceShowsNothing() {
    source.set { $0.appearance = nil }
    clock.advance(by: .seconds(10))
    XCTAssertEqual(shown.count, 0)
  }

  func testWithoutHideNotchOrNotchOrBandNothingIsShown() {
    let missing: [(inout MenuBarConditions) -> Void] = [
      { $0.hidesNotch = false }, { $0.hasNotch = false }, { $0.isBandOnScreen = false },
    ]
    for (index, remove) in missing.enumerated() {
      setUp()
      source.set(remove)
      turnLight()
      clock.advance(by: .seconds(10))
      XCTAssertEqual(shown.count, 0, "condition \(index)")
    }
  }

  func testAConditionLostBeforeTheDelayCancelsTheNotice() {
    let losses: [(inout MenuBarConditions) -> Void] = [
      { $0.appearance = .dark }, { $0.hidesNotch = false }, { $0.hasNotch = false },
      { $0.isBandOnScreen = false },
    ]
    for (index, lose) in losses.enumerated() {
      setUp()
      turnLight()
      clock.advance(by: .seconds(1))
      source.set(lose)
      clock.advance(by: .seconds(10))
      XCTAssertEqual(shown.count, 0, "condition \(index)")
    }
  }

  /// The band can go away without a report; the state is read again when the delay ends.
  func testTheStateIsReadAgainWhenTheDelayEnds() {
    turnLight()
    source.conditions.isBandOnScreen = false
    clock.advance(by: .seconds(2))
    XCTAssertEqual(shown.count, 0)
  }

  func testLightForLessThanTwoSecondsShowsNothing() {
    turnLight()
    clock.advance(by: .milliseconds(1500))
    turnDark()
    clock.advance(by: .seconds(10))
    XCTAssertEqual(shown.count, 0)
  }

  func testTheDelayStartsAgainAfterTheBarWasDark() {
    turnLight()
    clock.advance(by: .milliseconds(1500))
    turnDark()
    turnLight()
    clock.advance(by: .milliseconds(1500))
    XCTAssertEqual(shown.count, 0)
    clock.advance(by: .milliseconds(500))
    XCTAssertEqual(shown.count, 1)
  }

  func testRepeatedLightReportsDoNotPostponeTheNotice() {
    turnLight()
    clock.advance(by: .seconds(1))
    turnLight()
    clock.advance(by: .seconds(1))
    XCTAssertEqual(shown.count, 1)
  }

  func testASecondLightEventInTheSameLaunchShowsNothing() {
    turnLight()
    clock.advance(by: .seconds(2))
    shown.first?(.openSettings)
    turnDark()
    turnLight()
    clock.advance(by: .seconds(10))
    XCTAssertEqual(shown.count, 1)
  }

  func testNotNowShowsNothingForTheRestOfTheLaunch() {
    turnLight()
    clock.advance(by: .seconds(2))
    shown.first?(.notNow)
    XCTAssertEqual(coordinator?.answer, .notNow)
    for _ in 0..<3 {
      turnDark()
      turnLight()
      clock.advance(by: .seconds(10))
    }
    coordinator?.questionDidClose()
    XCTAssertEqual(shown.count, 1)
  }

  func testDuringTheUpdateQuestionTheNoticeWaitsForTheAnswer() {
    questionOnScreen = true
    turnLight()
    clock.advance(by: .seconds(10))
    XCTAssertEqual(shown.count, 0)
    questionOnScreen = false
    coordinator?.questionDidClose()
    XCTAssertEqual(shown.count, 1)
    coordinator?.questionDidClose()
    XCTAssertEqual(shown.count, 1)
  }

  func testAQueuedNoticeIsDroppedWhenTheBarTurnsDarkBeforeTheAnswer() {
    questionOnScreen = true
    turnLight()
    clock.advance(by: .seconds(2))
    turnDark()
    questionOnScreen = false
    coordinator?.questionDidClose()
    XCTAssertEqual(shown.count, 0)
    // It is not used up: a later grey bar still shows it.
    turnLight()
    clock.advance(by: .seconds(2))
    XCTAssertEqual(shown.count, 1)
  }

  func testTheEndOfTheQuestionAloneShowsNothing() {
    coordinator?.questionDidClose()
    turnLight()
    coordinator?.questionDidClose()
    XCTAssertEqual(shown.count, 0)
  }

  func testOnlyTheFirstAnswerCounts() {
    turnLight()
    clock.advance(by: .seconds(2))
    shown.first?(.notNow)
    shown.first?(.openSettings)
    XCTAssertEqual(coordinator?.answer, .notNow)
  }

  func testTheWallpaperSettingsLinkOpensThePaneAndFallsBackToSystemSettings() throws {
    let pane = try XCTUnwrap(GreyBarNoticeCoordinator.wallpaperSettingsURL)
    XCTAssertEqual(
      pane.absoluteString, "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")
    XCTAssertEqual(
      GreyBarNoticeCoordinator.systemSettingsBundleIdentifier, "com.apple.systempreferences")
    let app = URL(fileURLWithPath: "/System/Applications/System Settings.app")

    var opened: [URL] = []
    XCTAssertTrue(
      GreyBarNoticeCoordinator.openWallpaperSettings(
        open: {
          opened.append($0)
          return true
        }, systemSettings: { app }))
    XCTAssertEqual(opened, [pane])

    opened = []
    XCTAssertTrue(
      GreyBarNoticeCoordinator.openWallpaperSettings(
        open: {
          opened.append($0)
          return $0 == app
        }, systemSettings: { app }))
    XCTAssertEqual(opened, [pane, app])

    opened = []
    XCTAssertFalse(
      GreyBarNoticeCoordinator.openWallpaperSettings(
        open: {
          opened.append($0)
          return false
        }, systemSettings: { nil }))
    XCTAssertEqual(opened, [pane])
  }
}
