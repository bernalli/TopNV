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
}
