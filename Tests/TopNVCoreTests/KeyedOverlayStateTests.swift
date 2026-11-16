import XCTest
@testable import TopNVCore

final class KeyedOverlayStateTests: XCTestCase {
  typealias State = KeyedOverlayState

  private func input(
    active: [Int] = [], appearance: State.Appearance = .light,
    context: State.Context = .desktop, menu: Bool = true, enabled: Bool = true,
    time: Double = 10
  ) -> State.Input {
    .init(activeWindowIDs: active, appearance: appearance, context: context,
          menuVisible: menu, enabled: enabled, now: time)
  }

  func testCreationRequiresAllPositiveEvidence() {
    for appearance in [State.Appearance.light, .dark, .unknown] {
      for context in [State.Context.desktop, .fullScreen, .unknown] {
        for menu in [false, true] {
          for enabled in [false, true] {
            var state = State()
            let result = state.update(input(appearance: appearance, context: context,
                                            menu: menu, enabled: enabled))
            XCTAssertEqual(result.create != nil,
                           appearance == .light && context == .desktop && menu && enabled)
          }
        }
      }
    }
  }

  func testDuplicatesLeaveExactlyOneAndDoNotCreate() {
    for count in 1...20 {
      var state = State()
      let ids = Array(1...count)
      let result = state.update(input(active: ids.reversed() + ids))
      XCTAssertEqual(result.close, Array(ids.dropFirst()))
      XCTAssertEqual(result.gates, [1: true])
      XCTAssertNil(result.create)
    }
  }

  func testGateRemembersInactiveWindowsAndUnknownHidesOnlyActiveWindow() {
    var state = State()
    _ = state.update(input(active: [1]))
    state.spaceDidChange(now: 11)
    _ = state.update(input(active: [2], appearance: .dark, time: 12))
    XCTAssertEqual(state.visibility, [1: true, 2: false])
    _ = state.update(input(active: [1], appearance: .unknown, time: 13))
    XCTAssertEqual(state.visibility, [1: false, 2: false])
    _ = state.update(input(active: [1], time: 14))
    XCTAssertEqual(state.visibility, [1: true, 2: false])
  }

  func testPendingCreationIsReservedAndOldCommitCannotJoinNewVisit() throws {
    var state = State()
    let request = try XCTUnwrap(state.update(input()).create)
    XCTAssertNil(state.update(input(time: 11)).create)
    state.spaceDidChange(now: 12)
    XCTAssertFalse(state.commit(request, windowID: 1))
    XCTAssertNil(state.visibility[1])
    XCTAssertNil(state.update(input(time: 12.1)).create, "appearance must settle")
    let next = try XCTUnwrap(state.update(input(time: 13)).create)
    XCTAssertTrue(state.commit(next, windowID: 2))
    XCTAssertFalse(state.commit(next, windowID: 3), "commit is single-use")
  }

  func testRepeatedNotificationsNeverReplenishUnconfirmedVisitBudget() throws {
    var state = State()
    for attempt in 0..<3 {
      let time = Double(attempt * 10 + 10)
      let request = try XCTUnwrap(state.update(input(time: time)).create)
      XCTAssertTrue(state.commit(request, windowID: attempt + 1))
      for _ in 0..<20 { state.spaceDidChange(now: time + 1) }
    }
    for time in 40..<100 {
      state.spaceDidChange(now: Double(time))
      XCTAssertNil(state.update(input(time: Double(time) + 1)).create)
    }
    XCTAssertEqual(state.creationsThisVisit, 3)
    _ = state.update(input(active: [1], time: 101))
    state.spaceDidChange(now: 102)
    XCTAssertNotNil(state.update(input(time: 103)).create, "confirmed departure starts a visit")
  }

  func testMembershipOscillationWithoutSpaceChangeDoesNotReplenishVisitBudget() throws {
    var state = State()
    _ = state.update(input(active: [1], time: 10))
    for attempt in 0..<3 {
      let time = Double(20 + attempt * 10)
      let request = try XCTUnwrap(state.update(input(time: time)).create)
      XCTAssertTrue(state.commit(request, windowID: attempt + 2))
      _ = state.update(input(active: [1], time: time + 1))
    }
    XCTAssertEqual(state.creationsThisVisit, 3)
    XCTAssertNil(state.update(input(time: 50)).create)
  }

  func testNotificationWithSameConfirmedWindowDoesNotAuthorizeLaterBudgetReset() throws {
    var state = State()
    _ = state.update(input(active: [1], time: 10))
    state.spaceDidChange(now: 11)
    _ = state.update(input(active: [1], time: 12))
    for attempt in 0..<3 {
      let time = Double(20 + attempt * 10)
      let request = try XCTUnwrap(state.update(input(time: time)).create)
      XCTAssertTrue(state.commit(request, windowID: attempt + 2))
      _ = state.update(input(active: [1], time: time + 1))
    }
    XCTAssertEqual(state.creationsThisVisit, 3)
    XCTAssertNil(state.update(input(time: 50)).create)
  }

  func testRepeatedNotificationAfterNewWindowAppearsPreservesDepartureCandidate() throws {
    var state = State()
    _ = state.update(input(active: [1], time: 10))
    for attempt in 0..<3 {
      let time = Double(20 + attempt * 10)
      let request = try XCTUnwrap(state.update(input(time: time)).create)
      XCTAssertTrue(state.commit(request, windowID: attempt + 3))
      _ = state.update(input(active: [1], time: time + 1))
    }
    XCTAssertEqual(state.creationsThisVisit, 3)

    state.spaceDidChange(now: 41)
    _ = state.update(input(active: [2], time: 41.1))
    state.spaceDidChange(now: 41.2)
    _ = state.update(input(active: [2], time: 42))

    XCTAssertEqual(state.creationsThisVisit, 0, "the first confirmed departure starts B's visit")
    XCTAssertNotNil(state.update(input(time: 43)).create)
  }

  func testFullScreenWithRevealedMenuHidesExistingAndNeverCreates() {
    var state = State()
    _ = state.update(input(active: [1]))
    let result = state.update(input(active: [1, 2], context: .fullScreen, menu: true))
    XCTAssertNil(result.create)
    XCTAssertEqual(result.gates, [1: false])
    XCTAssertEqual(result.close, [2])
  }
}
