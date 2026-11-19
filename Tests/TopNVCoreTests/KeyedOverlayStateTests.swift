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

  func testFullScreenRefundsOnlyWindowsCommittedThisVisit() throws {
    var state = State()
    let previous = try XCTUnwrap(state.update(input(time: 10)).create)
    XCTAssertTrue(state.commit(previous, windowID: 1))
    _ = state.update(input(active: [1], time: 11))
    state.spaceDidChange(now: 12)

    for id in 2...4 {
      let request = try XCTUnwrap(state.update(input(time: Double(id + 11))).create)
      XCTAssertTrue(state.commit(request, windowID: id))
    }
    XCTAssertEqual(state.creationsThisVisit, 3)

    func fullScreen(_ id: Int, at time: Double) -> State.Input {
      .init(activeWindowIDs: [id], appearance: .light, context: .fullScreen,
            menuVisible: true, enabled: true, now: time, nativeFullScreen: true)
    }
    XCTAssertEqual(state.update(fullScreen(1, at: 16)).close, [1])
    XCTAssertEqual(state.creationsThisVisit, 3)
    XCTAssertEqual(state.update(fullScreen(2, at: 17)).close, [2])
    XCTAssertEqual(state.creationsThisVisit, 2)
    _ = state.update(fullScreen(2, at: 18))
    XCTAssertEqual(state.creationsThisVisit, 2)
  }

  func testFullScreenWithRevealedMenuHidesExistingAndNeverCreates() {
    var state = State()
    _ = state.update(input(active: [1]))
    let result = state.update(input(active: [1, 2], context: .fullScreen, menu: true))
    XCTAssertNil(result.create)
    XCTAssertEqual(result.gates, [1: false])
    XCTAssertEqual(result.close, [2])
  }

  func testArrivalKeepsTheRememberedGateUntilTheEvidenceSettles() {
    var state = State()
    _ = state.update(input(active: [1], time: 10))
    state.spaceDidChange(now: 20)
    _ = state.update(input(active: [2], appearance: .dark, time: 21))
    XCTAssertEqual(state.visibility, [1: true, 2: false])

    // Back on the light Space: every evidence value may still be stale.
    state.spaceDidChange(now: 30)
    for appearance in [State.Appearance.light, .dark, .unknown] {
      for context in [State.Context.desktop, .fullScreen, .unknown] {
        for menu in [false, true] {
          let result = state.update(input(active: [1], appearance: appearance, context: context,
                                          menu: menu, time: 30.2))
          XCTAssertEqual(result.gates, [:])
          XCTAssertNil(result.create)
        }
      }
    }
    XCTAssertEqual(state.visibility, [1: true, 2: false])
    XCTAssertEqual(state.update(input(active: [1], time: 30.5)).gates, [1: true])

    // On the dark Space the hidden window stays hidden, also while a stale probe says light.
    state.spaceDidChange(now: 40)
    XCTAssertEqual(state.update(input(active: [2], time: 40.2)).gates, [:])
    XCTAssertEqual(state.visibility, [1: true, 2: false])
    XCTAssertEqual(state.update(input(active: [2], appearance: .dark, time: 40.5)).gates,
                   [2: false])
  }

  func testDuplicatesAreClosedAlsoWhileTheEvidenceSettles() {
    var state = State()
    _ = state.update(input(active: [1], time: 10))
    state.spaceDidChange(now: 20)
    let result = state.update(input(active: [3, 1, 2], time: 20.1))
    XCTAssertEqual(result.close, [2, 3])
    XCTAssertEqual(result.gates, [:])
  }

  func testForgetDoesNotRefillTheBudgetAndANewValueDoes() throws {
    var state = State()
    for attempt in 0..<3 {
      let time = Double(10 + attempt * 10)
      let request = try XCTUnwrap(state.update(input(time: time)).create)
      XCTAssertTrue(state.commit(request, windowID: attempt + 1))
      _ = state.update(input(active: [attempt + 1], time: time + 1))
      state.forget(attempt + 1)
      state.forget(attempt + 1)
      state.forget(-1)
    }
    XCTAssertNil(state.update(input(time: 50)).create)
    state = State()
    XCTAssertNotNil(state.update(input(time: 51)).create)
  }

  func testWindowReplacementPreservesSpaceSettling() throws {
    var state = State()
    _ = state.update(input(active: [7], time: 10))
    state.spaceDidChange(now: 12)
    state.resetForWindowReplacement()

    XCTAssertTrue(state.visibility.isEmpty)
    for time in [12.0, 12.01, 12.25, 12.499] {
      XCTAssertNil(state.update(input(time: time)).create)
    }
    XCTAssertNil(state.update(input(appearance: .dark, time: 12.5)).create)
    let reservation = try XCTUnwrap(state.update(input(time: 12.5)).create)
    XCTAssertTrue(state.commit(reservation, windowID: 7))
    XCTAssertEqual(state.visibility, [7: false])
  }

  func testWindowReplacementInvalidatesReservationsAndRefillsAnEmptyDisplayBudget() throws {
    var state = State()
    var obsolete: [State.Reservation] = []
    for time in [10.0, 11, 12] {
      _ = state.update(input(appearance: .dark, time: time))
      obsolete.append(try XCTUnwrap(state.update(input(time: time)).create))
    }
    XCTAssertTrue(state.visibility.isEmpty)
    XCTAssertEqual(state.creationsThisVisit, 3)
    XCTAssertNil(state.update(input(time: 20)).create)

    state.resetForWindowReplacement()
    let fresh = try XCTUnwrap(state.update(input(time: 20)).create)
    for reservation in obsolete {
      XCTAssertFalse(state.commit(reservation, windowID: 7))
    }
    XCTAssertTrue(state.commit(fresh, windowID: 7))
    XCTAssertFalse(state.commit(fresh, windowID: 8))
  }

  func testNonFiniteOrBackwardTimeNeverCreatesMoreThanTheBudget() {
    var state = State()
    var created = 0
    for time in [Double.nan, -.infinity, -1, 0, .infinity, 5, .nan, 4, 3, .infinity, 100, 1] {
      state.spaceDidChange(now: time)
      if let request = state.update(input(time: time)).create {
        created += 1
        XCTAssertTrue(state.commit(request, windowID: created))
      }
    }
    XCTAssertLessThanOrEqual(created, 3)
  }

  /// Any order of notifications, membership changes, evidence changes, commits and forgotten
  /// windows keeps these properties.
  func testRandomTransitionsKeepTheInvariants() {
    var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    func next(_ bound: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int((seed >> 33) % UInt64(bound))
    }
    for _ in 0..<300 {
      var state = State()
      var now = 1.0
      var known: [Int] = []
      var nextID = 1
      var sinceConfirmedDeparture = 0
      var lastKeeper: Int?
      var candidate: Int?
      var settleUntil = 0.0
      for _ in 0..<120 {
        now += [0.01, 0.1, 0.3, 0.6][next(4)]
        if next(4) == 0 {
          state.spaceDidChange(now: now)
          if candidate == nil { candidate = lastKeeper }
          settleUntil = now + 0.5
          continue
        }
        var active = known.filter { _ in next(3) == 0 }
        if next(8) == 0, let first = active.first { active.append(first) }
        if next(8) == 0 { active.append(1000 + next(3)) }
        active.reverse()
        let appearance = [State.Appearance.light, .light, .light, .dark, .unknown][next(5)]
        let context = [State.Context.desktop, .desktop, .desktop, .fullScreen, .unknown][next(5)]
        let menu = next(6) != 0
        let enabled = next(12) != 0
        let revealed = next(2) == 0
        let allPositive = appearance == .light && context == .desktop && menu && enabled
        let result = state.update(.init(
          activeWindowIDs: active, appearance: appearance, context: context, menuVisible: menu,
          enabled: enabled, now: now, desktopRevealed: revealed))
        let target = now >= settleUntil && allPositive ? Set(active).min() : nil
        XCTAssertEqual(result.keyChange?.windowID, target)
        XCTAssertEqual(result.keyChange?.key, target.map { _ in revealed ? .revealed : .normal })

        let distinct = Set(active).sorted()
        if let candidate, now >= settleUntil, !distinct.contains(candidate) {
          sinceConfirmedDeparture = 0
        }
        if now >= settleUntil { candidate = nil }
        lastKeeper = distinct.first

        XCTAssertEqual(result.close, Array(distinct.dropFirst()))
        XCTAssertTrue(result.gates.keys.allSatisfy { $0 == distinct.first })
        for (_, shown) in result.gates where shown { XCTAssertTrue(allPositive) }
        if now < settleUntil {
          // Turning the option off is certain while the evidence settles: it hides at once.
          if !enabled, let keeper = distinct.first {
            XCTAssertEqual(result.gates, [keeper: false])
          } else {
            XCTAssertTrue(result.gates.isEmpty)
          }
        }
        if let request = result.create {
          XCTAssertTrue(distinct.isEmpty)
          XCTAssertTrue(allPositive)
          XCTAssertGreaterThanOrEqual(now, settleUntil)
          sinceConfirmedDeparture += 1
          XCTAssertLessThanOrEqual(sinceConfirmedDeparture, 3)
          if next(5) != 0, state.commit(request, windowID: nextID) {
            XCTAssertFalse(state.commit(request, windowID: nextID + 1))
            known.append(nextID)
            nextID += 2
          }
        }
        if next(15) == 0, let victim = known.first {
          state.forget(victim)
          known.removeFirst()
        }
      }
    }
  }
}
