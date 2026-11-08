import XCTest
@testable import TopNVCore

@MainActor
final class FakeUpdater: UpdaterControlling {
  var events: [String] = []
  var canCheckForUpdates = true
  var automaticallyChecksForUpdates = true {
    didSet { events.append("automatic:\(automaticallyChecksForUpdates)"); onSet?() }
  }
  var onSet: (() -> Void)?
  var onStart: (() -> Void)?
  var fails = false
  func start() throws { events.append("start"); onStart?(); if fails { throw NSError(domain: "test", code: 1) } }
  func checkForUpdates() { events.append("check") }
}

final class UpdateCoordinatorTests: XCTestCase {
  @MainActor func testAnswersPersistMarkerBeforeQuestionAndStartOnlyOnce() {
    for answer in [AutomaticUpdateAnswer.enable, .decline, .dismissed] {
      let name="test.updates.\(UUID())", defaults=UserDefaults(suiteName: "test.updates.\(UUID())")!
      defer { defaults.removeObject(forKey: "automaticUpdateQuestionAsked") }
      _ = name
      let updater=FakeUpdater(); var ready=0; var reply: ((AutomaticUpdateAnswer) -> Void)?
      let coordinator=UpdateCoordinator(configuration: UpdateConfiguration(infoDictionary: UpdateConfigurationTests.valid), updater: updater, defaults: defaults, ask: { completion in
        XCTAssertNotNil(defaults.object(forKey: "automaticUpdateQuestionAsked"))
        XCTAssertEqual(updater.events,["automatic:false"])
        reply=completion
      }, onReady: { ready += 1 })
      coordinator.start(); coordinator.start()
      XCTAssertEqual(coordinator.state,.awaitingAnswer); XCTAssertEqual(ready,0)
      reply?(answer); reply?(.enable); coordinator.start()
      XCTAssertEqual(coordinator.state,.ready); XCTAssertEqual(ready,1)
      XCTAssertEqual(updater.events,["automatic:false","automatic:\(answer == .enable)","start"])
    }
  }
  @MainActor func testExistingMarkerOfAnyTypePreservesPreferenceOnUpgrade() {
    for marker in [false, "malformed", 0] as [Any] {
      let defaults=UserDefaults(suiteName: "test.updates.\(UUID())")!
      defer { defaults.removeObject(forKey: "automaticUpdateQuestionAsked") }
      defaults.set(marker,forKey:"automaticUpdateQuestionAsked")
      let updater=FakeUpdater()
      let coordinator=UpdateCoordinator(configuration: UpdateConfiguration(infoDictionary: UpdateConfigurationTests.valid),updater:updater,defaults:defaults,ask:{ _ in XCTFail("must not ask again") })
      coordinator.start(); XCTAssertEqual(updater.events,["start"]); XCTAssertEqual(coordinator.state,.ready)
    }
  }
  @MainActor func testUnavailableAndFailedStartDoNotBecomeReady() {
    for valid in [false,true] {
      let defaults=UserDefaults(suiteName:"test.updates.\(UUID())")!
      defer { defaults.removeObject(forKey:"automaticUpdateQuestionAsked") }
      let updater=FakeUpdater(); updater.fails=true
      let coordinator=UpdateCoordinator(configuration:UpdateConfiguration(infoDictionary:valid ? UpdateConfigurationTests.valid:nil),updater:updater,defaults:defaults,ask:{$0(.decline)},onReady:{XCTFail("failed updater cannot be ready")})
      coordinator.start(); XCTAssertEqual(coordinator.state,.failed)
      XCTAssertEqual(defaults.object(forKey:"automaticUpdateQuestionAsked") != nil,valid)
    }
    let defaults=UserDefaults(suiteName:"test.updates.\(UUID())")!
    let absent=UpdateCoordinator(configuration:UpdateConfiguration(infoDictionary:UpdateConfigurationTests.valid),updater:nil,defaults:defaults,ask:{_ in XCTFail("no updater")})
    absent.start(); XCTAssertNil(defaults.object(forKey:"automaticUpdateQuestionAsked"))
  }
  @MainActor func testReentrantCallbacksCannotChangeConsumedAnswer() {
    let defaults=UserDefaults(suiteName:"test.updates.\(UUID())")!
    defer { defaults.removeObject(forKey:"automaticUpdateQuestionAsked") }
    let updater=FakeUpdater(); var reply: ((AutomaticUpdateAnswer)->Void)?
    let coordinator=UpdateCoordinator(configuration:UpdateConfiguration(infoDictionary:UpdateConfigurationTests.valid),updater:updater,defaults:defaults,ask:{reply=$0})
    updater.onSet={ reply?(.enable); coordinator.start() }
    updater.onStart={ reply?(.enable); coordinator.start() }
    coordinator.start(); reply?(.decline)
    XCTAssertEqual(updater.events,["automatic:false","automatic:false","start"])
    XCTAssertEqual(coordinator.state,.ready)
  }
}
