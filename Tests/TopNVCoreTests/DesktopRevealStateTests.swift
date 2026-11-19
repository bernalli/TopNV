import XCTest
@testable import TopNVCore

final class DesktopRevealStateTests: XCTestCase {
  private typealias State = KeyedOverlayState

  private func sample(_ active: [Int], _ now: Double, revealed: Bool = false,
                      menu: Bool = true, sliding: Bool = false, context: State.Context = .desktop,
                      native: Bool = false, enabled: Bool = true) -> State.Input {
    .init(activeWindowIDs: active, appearance: .light, context: context, menuVisible: menu,
          enabled: enabled, now: now, desktopRevealed: revealed, spaceSliding: sliding, nativeFullScreen: native)
  }

  func testRepeatedRevealsReuseTheWindowAndRestoreItOnTheFirstSample() throws {
    var state = State()
    let reservation = try XCTUnwrap(state.update(sample([], 1)).create)
    XCTAssertTrue(state.commit(reservation, windowID: 7))
    XCTAssertEqual(state.update(sample([7], 1.1)).gates, [7: true])
    for index in 0..<10 {
      let now = 2 + Double(index)
      for revealed in [true, true, false] {
        let result = state.update(sample([7, 7], now, revealed: revealed))
        XCTAssertEqual(result.gates, [7: !revealed])
        XCTAssertEqual(state.visibility, [7: !revealed])
        XCTAssertTrue(result.close.isEmpty)
        XCTAssertNil(result.create)
        XCTAssertEqual(state.creationsThisVisit, 1)
      }
    }
  }

  func testRevealCancelsAnUncommittedReservationAndNeverReservesWhileRevealed() throws {
    var state = State()
    let obsolete = try XCTUnwrap(state.update(sample([], 1)).create)
    for now in [1.1, 2, 4, 3] {
      XCTAssertNil(state.update(sample([], now, revealed: true)).create)
      XCTAssertFalse(state.commit(obsolete, windowID: 7))
      XCTAssertEqual(state.creationsThisVisit, 1)
    }
    XCTAssertNotNil(state.update(sample([], 4)).create)
  }

  func testRevealDuringSlideRestoresOnlyThePreviouslyVisibleWindow() {
    var state = State()
    _ = state.update(sample([8], 1, menu: false))
    _ = state.update(sample([7], 2))
    state.spaceDidChange(now: 3)
    for window in [7, 8] {
      let hidden = state.update(sample([window], 3.1, revealed: true, sliding: true))
      XCTAssertEqual(hidden.gates, [window: false])
      XCTAssertTrue(hidden.close.isEmpty)
    }
    XCTAssertEqual(state.update(sample([8], 3.2, sliding: true)).gates, [7: true])
    XCTAssertEqual(state.visibility, [7: true, 8: false])
    XCTAssertTrue(state.update(sample([7], 3.3, sliding: true)).gates.isEmpty)
    XCTAssertEqual(state.creationsThisVisit, 0)
  }

  func testRevealMasksBothSlidingWindowsWhenActiveMembershipChanges() throws {
    for active in [[8], []] {
      var state = State()
      let first = try XCTUnwrap(state.update(sample([], 1)).create)
      XCTAssertTrue(state.commit(first, windowID: 7))
      _ = state.update(sample([7], 1.1))
      state.spaceDidChange(now: 2)
      let second = try XCTUnwrap(state.update(sample([], 2.5)).create)
      XCTAssertTrue(state.commit(second, windowID: 8))
      _ = state.update(sample([8], 2.6))
      XCTAssertEqual(state.visibility, [7: true, 8: true])

      let reveal = state.update(sample(active, 3, revealed: true, sliding: true))
      XCTAssertEqual(reveal.gates, [7: false, 8: false], "active: \(active)")
      XCTAssertEqual(state.visibility, [7: false, 8: false])
      XCTAssertTrue(reveal.close.isEmpty)
      XCTAssertNil(reveal.create)
      XCTAssertEqual(state.creationsThisVisit, 1)

      let invalidExit = state.update(sample([8], .infinity, sliding: true))
      XCTAssertTrue(invalidExit.gates.isEmpty)
      XCTAssertEqual(state.visibility, [7: false, 8: false])

      let restore = state.update(sample(active, 3.1, sliding: true))
      XCTAssertEqual(restore.gates, [7: true, 8: true])
      XCTAssertEqual(state.visibility, [7: true, 8: true])
      XCTAssertTrue(restore.close.isEmpty)
      XCTAssertNil(restore.create)
      XCTAssertEqual(state.creationsThisVisit, 1)
      XCTAssertTrue(state.update(sample([7], 3.2, menu: false, sliding: true)).gates.isEmpty)
      XCTAssertEqual(state.visibility, [7: true, 8: true])
    }
  }

  func testRestoringWithTransientlyEmptyMembershipDoesNotSpendTheBudget() throws {
    var state = State()
    let request = try XCTUnwrap(state.update(sample([], 1)).create)
    XCTAssertTrue(state.commit(request, windowID: 7))
    _ = state.update(sample([7], 1.1))
    _ = state.update(sample([7], 2, revealed: true))

    let restore = state.update(sample([], 2.1))
    XCTAssertEqual(restore.gates, [7: true])
    XCTAssertNil(restore.create)
    XCTAssertNil(state.update(sample([], 2.2)).create)
    XCTAssertNil(state.update(sample([7], 2.3)).create)
    XCTAssertEqual(state.creationsThisVisit, 1)
  }

  func testRestoringWithPersistentlyEmptyMembershipAllowsCreationAfterTheRetryInterval() throws {
    var state = State()
    let request = try XCTUnwrap(state.update(sample([], 1)).create)
    XCTAssertTrue(state.commit(request, windowID: 7))
    _ = state.update(sample([7], 1.1))
    _ = state.update(sample([7], 2, revealed: true))

    XCTAssertNil(state.update(sample([], 2.125)).create)
    XCTAssertNil(state.update(sample([], 2.5)).create)
    XCTAssertNotNil(state.update(sample([], 2.625)).create)
    XCTAssertEqual(state.creationsThisVisit, 2)
  }

  func testConfirmedDepartureAllowsCreationWhenTheNewSpaceIsEmpty() throws {
    for restoresBeforeSettling in [false, true] {
      var state = State()
      let request = try XCTUnwrap(state.update(sample([], 1)).create)
      XCTAssertTrue(state.commit(request, windowID: 7))
      _ = state.update(sample([7], 1.1))
      _ = state.update(sample([7], 2, revealed: true))
      state.spaceDidChange(now: 3)

      if restoresBeforeSettling {
        let restore = state.update(sample([], 3.25))
        XCTAssertEqual(restore.gates, [7: true])
        XCTAssertNil(restore.create)
      }
      let arrival = state.update(sample([], 3.5))
      XCTAssertNotNil(arrival.create)
      XCTAssertEqual(state.creationsThisVisit, 1)
    }
  }

  func testMalformedRevealHidesImmediatelyAndAnInvalidExitCannotShow() {
    for now in [Double.nan, -.infinity, .infinity, 1] {
      var state = State()
      _ = state.update(sample([7], 2))
      state.spaceDidChange(now: 3)
      let hidden = state.update(sample([9, 7, 9], now, revealed: true, menu: false))
      XCTAssertEqual(hidden.close, [9])
      XCTAssertEqual(hidden.gates, [7: false])
      for context in [State.Context.unknown, .fullScreen, .desktop] {
        _ = state.update(sample([7], now, menu: false, context: context))
        XCTAssertEqual(state.visibility[7], false)
      }
      for invalid in [Double.nan, -.infinity, .infinity] {
        _ = state.update(sample([7], invalid))
        XCTAssertEqual(state.visibility[7], false)
      }
      XCTAssertEqual(state.update(sample([7], 4)).gates, [7: true])
    }
  }

  func testAnUntimedNotificationCannotConfirmADepartureAndRefillTheBudget() throws {
    for invalid in [Double.nan, -.infinity, .infinity] {
      var state = State()
      let request = try XCTUnwrap(state.update(sample([], 1)).create)
      XCTAssertTrue(state.commit(request, windowID: 7))
      _ = state.update(sample([7], 2, revealed: true))
      state.spaceDidChange(now: invalid)
      _ = state.update(sample([], 3, revealed: true))
      XCTAssertEqual(state.creationsThisVisit, 1)
      XCTAssertEqual(state.update(sample([7], 3.1)).gates, [7: true])
    }
  }

  func testRevealedFullScreenHonorsNativeClosureOnlyAfterSettling() throws {
    var state = State()
    let request = try XCTUnwrap(state.update(sample([], 1)).create)
    XCTAssertTrue(state.commit(request, windowID: 7))
    _ = state.update(sample([7], 2))
    let slide = state.update(sample([7], 3, revealed: true, sliding: true, context: .fullScreen, native: true))
    XCTAssertEqual(slide.gates, [7: false])
    XCTAssertTrue(slide.close.isEmpty)
    let covered = state.update(sample([7], 3.5, revealed: true, context: .fullScreen))
    XCTAssertTrue(covered.close.isEmpty)
    XCTAssertEqual(covered.gates, [7: false])
    XCTAssertEqual(state.creationsThisVisit, 1)
    XCTAssertEqual(state.update(sample([7], 4, revealed: true, context: .fullScreen, native: true)).close, [7])
    XCTAssertEqual(state.creationsThisVisit, 0)
  }
}
