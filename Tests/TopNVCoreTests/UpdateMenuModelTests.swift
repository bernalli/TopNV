import XCTest
import Combine
@testable import TopNVCore

final class UpdateMenuModelTests: XCTestCase {
  @MainActor func testCommandsHaveNoEffectBeforeReadyAndRespectCanCheck() {
    let updater=FakeUpdater(); updater.automaticallyChecksForUpdates=false; updater.events=[]
    let model=UpdateMenuModel(updater:updater)
    model.checkForUpdates(); model.setAutomaticallyChecks(true)
    XCTAssertTrue(updater.events.isEmpty); XCTAssertFalse(model.isAvailable)
    model.updaterDidStart(); model.checkForUpdates()
    XCTAssertEqual(updater.events,["check"]); XCTAssertFalse(model.automaticallyChecksForUpdates)
    updater.canCheckForUpdates=false; model.checkForUpdates()
    XCTAssertEqual(updater.events,["check"])
    model.setAutomaticallyChecks(true); XCTAssertTrue(model.automaticallyChecksForUpdates)
  }
  @MainActor func testQueuedChangesReadCurrentStateAndDoNotPublishEqualValues() {
    let updater=FakeUpdater(); var queued: [@MainActor ()->Void]=[]
    let model=UpdateMenuModel(updater:updater,schedule:{queued.append($0)})
    model.updaterDidStart(); var publications=0
    let subscription=model.objectWillChange.sink { publications += 1 }
    updater.canCheckForUpdates=false; model.updaterDidChange()
    XCTAssertTrue(model.canCheckForUpdates); XCTAssertEqual(publications,0)
    updater.canCheckForUpdates=true; model.updaterDidChange()
    queued.reversed().forEach{$0()}; XCTAssertTrue(model.canCheckForUpdates); XCTAssertEqual(publications,0)
    queued=[]; updater.automaticallyChecksForUpdates=false; model.updaterDidChange()
    queued.forEach{$0()}; XCTAssertFalse(model.automaticallyChecksForUpdates); XCTAssertEqual(publications,1)
    queued=[]; model.updaterDidChange(); queued.forEach{$0()}; XCTAssertEqual(publications,1)
    withExtendedLifetime(subscription) {}
  }
  @MainActor func testAbsentUpdaterAndEarlyNotificationsStayUnavailable() {
    let model=UpdateMenuModel(updater:nil,schedule:{$0()})
    model.updaterDidStart(); model.updaterDidChange(); model.setAutomaticallyChecks(true); model.checkForUpdates()
    XCTAssertFalse(model.isAvailable); XCTAssertFalse(model.canCheckForUpdates)
    let updater=FakeUpdater(); let pending=UpdateMenuModel(updater:updater,schedule:{$0()})
    pending.updaterDidChange(); XCTAssertFalse(pending.isAvailable); XCTAssertFalse(pending.canCheckForUpdates)
  }
  @MainActor func testTheMenuSeesAWaitingUpdaterUntilItStartsOrFails() {
    XCTAssertEqual(UpdateMenuModel(updater: nil).items, .hidden)
    let updater = FakeUpdater(); updater.automaticallyChecksForUpdates = false; updater.events = []
    let model = UpdateMenuModel(updater: updater, schedule: { $0() })
    XCTAssertTrue(model.isWaiting); XCTAssertEqual(model.items, .waiting)
    model.updaterDidChange(); XCTAssertEqual(model.items, .waiting)
    model.checkForUpdates(); model.setAutomaticallyChecks(true)
    XCTAssertTrue(updater.events.isEmpty)
    model.updaterDidStart()
    XCTAssertFalse(model.isWaiting)
    XCTAssertEqual(model.items, .ready(canCheck: true, checksAutomatically: false))
    // A failure reported after the start changes nothing.
    model.updaterDidFail(); XCTAssertEqual(model.items, .ready(canCheck: true, checksAutomatically: false))
    let failing = UpdateMenuModel(updater: FakeUpdater(), schedule: { $0() })
    failing.updaterDidFail(); failing.updaterDidFail()
    XCTAssertFalse(failing.isWaiting); XCTAssertEqual(failing.items, .hidden)
  }
  @MainActor func testItemsFollowEveryReadyStateAndPublishOnlyChanges() {
    for canCheck in [true, false] {
      for automatic in [true, false] {
        let updater = FakeUpdater(); updater.canCheckForUpdates = canCheck
        updater.automaticallyChecksForUpdates = automatic
        let model = UpdateMenuModel(updater: updater, schedule: { $0() })
        model.updaterDidStart()
        XCTAssertEqual(model.items, .ready(canCheck: canCheck, checksAutomatically: automatic))
        XCTAssertEqual(model.items.canCheck, canCheck)
        XCTAssertEqual(model.items.checksAutomatically, automatic)
        XCTAssertTrue(model.items.isReady)
      }
    }
    for items in [UpdateItems.hidden, .waiting] {
      XCTAssertFalse(items.isReady); XCTAssertFalse(items.canCheck); XCTAssertFalse(items.checksAutomatically)
    }
    let model = UpdateMenuModel(updater: FakeUpdater(), schedule: { $0() })
    var publications = 0
    let subscription = model.objectWillChange.sink { publications += 1 }
    model.updaterDidFail(); model.updaterDidFail()
    XCTAssertEqual(publications, 1)
    withExtendedLifetime(subscription) {}
  }
}
