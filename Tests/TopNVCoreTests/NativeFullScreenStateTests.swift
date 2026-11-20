import XCTest
@testable import TopNVCore

/// Negative and property tests for the native full-screen transition of the state and for the
/// evidence that feeds it.
final class NativeFullScreenStateTests: XCTestCase {
  typealias State = KeyedOverlayState

  private func desktop(_ active: [Int], _ now: Double) -> State.Input {
    .init(activeWindowIDs: active, appearance: .light, context: .desktop, menuVisible: true,
          enabled: true, now: now)
  }

  private func native(_ active: [Int], _ now: Double, context: State.Context = .fullScreen,
                      sliding: Bool = false) -> State.Input {
    .init(activeWindowIDs: active, appearance: .light, context: context, menuVisible: true,
          enabled: true, now: now, spaceSliding: sliding, nativeFullScreen: true)
  }

  // MARK: - Visit budget

  /// Another process in front for a moment creates a window in the full-screen Space, which
  /// the next native sample closes. The desktop visited afterwards still gets its window.
  func testWindowsClosedInAFullScreenSpaceDoNotStarveTheNextDesktop() throws {
    var state = State()
    let first = try XCTUnwrap(state.update(desktop([], 1)).create)
    XCTAssertTrue(state.commit(first, windowID: 1))
    _ = state.update(desktop([1], 1.1))
    state.spaceDidChange(now: 2)
    XCTAssertTrue(state.update(native([], 2.6)).close.isEmpty)
    for round in 0..<6 {
      let now = 3 + Double(round)
      let id = 10 + round
      let request = try XCTUnwrap(state.update(desktop([], now)).create, "round \(round)")
      XCTAssertTrue(state.commit(request, windowID: id))
      XCTAssertEqual(state.update(native([id], now + 0.1)).close, [id])
      state.forget(id)
      XCTAssertEqual(state.creationsThisVisit, 0)
    }
    state.spaceDidChange(now: 20)
    XCTAssertNotNil(state.update(desktop([], 20.6)).create)
  }

  /// Two displays: the frontmost app is full screen on the other one and has a zoomed window
  /// here. Every return of the desktop classification gets a window, without a Space switch.
  func testAnAlternatingClassificationNeverLeavesTheDesktopWithoutAWindow() throws {
    var state = State()
    for round in 0..<8 {
      let now = 1 + Double(round)
      let request = try XCTUnwrap(state.update(desktop([], now)).create, "round \(round)")
      XCTAssertTrue(state.commit(request, windowID: round + 1))
      XCTAssertEqual(state.update(desktop([round + 1], now + 0.1)).gates, [round + 1: true])
      XCTAssertEqual(state.update(native([round + 1], now + 0.2)).close, [round + 1])
      state.forget(round + 1)
    }
  }

  /// A creation whose window never joins the Space stays spent, in a full-screen Space too.
  func testAnUnconfirmedCreationIsNotReturnedByNativeFullScreen() throws {
    var state = State()
    for round in 0..<3 {
      let now = 1 + Double(round)
      let request = try XCTUnwrap(state.update(desktop([], now)).create)
      XCTAssertTrue(state.commit(request, windowID: round + 1))
      XCTAssertTrue(state.update(native([], now + 0.1)).close.isEmpty)
    }
    XCTAssertEqual(state.creationsThisVisit, 3)
    XCTAssertNil(state.update(desktop([], 10)).create)
    // The refund never goes below zero and never exceeds the windows that were closed.
    XCTAssertEqual(state.update(native([1], 11)).close, [1])
    XCTAssertEqual(state.creationsThisVisit, 2)
    XCTAssertEqual(state.update(native([2, 3, 2], 12)).close, [2, 3])
    XCTAssertEqual(state.creationsThisVisit, 0)
    XCTAssertEqual(state.update(native([4, 5], 13)).close, [4, 5])
    XCTAssertEqual(state.creationsThisVisit, 0)
  }

  // MARK: - Malformed and unsettled transitions

  func testNativeEvidenceWithoutAFullScreenContextNeverClosesTheKeeper() {
    for context in [State.Context.desktop, .unknown] {
      var state = State()
      _ = state.update(desktop([7], 1))
      let result = state.update(native([7, 8], 2, context: context))
      XCTAssertEqual(result.close, [8], "\(context)")
      XCTAssertEqual(result.gates, [7: context == .desktop], "\(context)")
      XCTAssertNil(result.create)
      XCTAssertEqual(state.creationsThisVisit, 0)
    }
  }

  func testWhileTheEvidenceSettlesOrSlidesNativeFullScreenClosesNothing() {
    var state = State()
    _ = state.update(desktop([7], 1))
    // A slide into the full-screen Space: the window that leaves keeps its gate.
    for step in 0..<20 {
      let result = state.update(native([7], 2 + Double(step) * 0.1, sliding: true))
      XCTAssertTrue(result.close.isEmpty, "step \(step)")
      XCTAssertTrue(result.gates.isEmpty, "step \(step)")
    }
    state.spaceDidChange(now: 4)
    for now in [4.0, 4.2, 4.49] {
      XCTAssertTrue(state.update(native([7], now)).close.isEmpty, "\(now)")
    }
    XCTAssertEqual(state.visibility, [7: true])
    XCTAssertEqual(state.update(native([7], 4.5)).close, [7])
  }

  func testANonNumberTimeNeverClosesAndTheOptionOffHidesAtOnce() {
    var state = State()
    _ = state.update(desktop([7], 1))
    state.spaceDidChange(now: 2)
    XCTAssertTrue(state.update(native([7], .nan)).close.isEmpty)
    let off = state.update(.init(activeWindowIDs: [7], appearance: .light, context: .fullScreen,
                                 menuVisible: true, enabled: false, now: 2.1, nativeFullScreen: true))
    XCTAssertTrue(off.close.isEmpty)
    XCTAssertEqual(off.gates, [7: false])
  }

  /// The properties of one sample. The model: `settled`, and `closesAll` when the sample is
  /// also full screen and native.
  private func check(_ result: State.Decision, _ state: State, input: State.Input, before: Int,
                     model: (closesAll: Bool, settled: Bool)) {
    let distinct = Set(input.activeWindowIDs).sorted()
    if model.closesAll {
      XCTAssertEqual(result.close, distinct)
      XCTAssertTrue(result.gates.isEmpty)
      XCTAssertNil(result.create)
      // Only windows committed in this visit are refunded, at most one creation each. A
      // confirmed departure in the same sample can already have emptied the count.
      XCTAssertLessThanOrEqual(state.creationsThisVisit, before)
      XCTAssertTrue(state.creationsThisVisit == 0
                      || state.creationsThisVisit >= before - distinct.count)
      XCTAssertTrue(distinct.allSatisfy { state.visibility[$0] == nil })
    } else {
      XCTAssertEqual(result.close, Array(distinct.dropFirst()))
      XCTAssertTrue(result.gates.keys.allSatisfy { $0 == distinct.first })
    }
    for (_, shown) in result.gates where shown { XCTAssertEqual(input.context, .desktop) }
    XCTAssertTrue((0...3).contains(state.creationsThisVisit))
    if result.create != nil {
      XCTAssertTrue(distinct.isEmpty)
      XCTAssertTrue(model.settled && input.context == .desktop && input.appearance == .light)
      XCTAssertTrue(input.enabled && input.menuVisible)
      XCTAssertGreaterThanOrEqual(state.creationsThisVisit, 1)
    }
  }

  /// Any order of notifications, memberships and evidence, with native full screen among them.
  func testRandomTransitionsWithNativeFullScreenKeepTheInvariants() {
    var seed: UInt64 = 0x2545_F491_4F6C_DD1D
    func next(_ bound: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int((seed >> 33) % UInt64(bound))
    }
    for _ in 0..<300 {
      var state = State()
      var now = 1.0
      var known: [Int] = []
      var settleUntil = 0.0
      for step in 0..<150 {
        now += [0.01, 0.1, 0.3, 0.6][next(4)]
        if next(5) == 0 {
          state.spaceDidChange(now: now)
          settleUntil = now + 0.5
          continue
        }
        var active = known.filter { _ in next(3) == 0 }
        if next(8) == 0, let first = active.first { active.append(first) }
        active.reverse()
        let input = State.Input(
          activeWindowIDs: active, appearance: [.light, .light, .dark, .unknown][next(4)],
          context: [.desktop, .desktop, .fullScreen, .fullScreen, .unknown][next(5)],
          menuVisible: next(6) != 0, enabled: next(12) != 0, now: now, nativeFullScreen: next(2) == 0)
        let before = state.creationsThisVisit
        let result = state.update(input)
        let settled = now >= settleUntil
        check(result, state, input: input, before: before,
              model: (settled && input.context == .fullScreen && input.nativeFullScreen, settled))
        if let request = result.create, next(4) != 0, state.commit(request, windowID: step + 1) {
          known.append(step + 1)
        }
        for id in result.close {
          state.forget(id)
          known.removeAll { $0 == id }
        }
      }
    }
  }
}

// MARK: - Evidence

extension NativeFullScreenStateTests {
  private var screen: CGRect { CGRect(x: 0, y: 0, width: 1512, height: 982) }
  private var band: CGRect { CGRect(x: 0, y: 949, width: 1512, height: 33) }
  private var visible: CGRect { CGRect(x: 0, y: 0, width: 1512, height: 949) }

  private func row(pid: Int32, owner: String? = "Browser", top: Int = 148, height: Int = 834,
                   left: Int = 0, width: Int = 1512, layer: Int = 0, alpha: Double = 1) -> [String: Any] {
    var result: [String: Any] = [
      kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer,
      kCGWindowAlpha as String: alpha,
      kCGWindowBounds as String: ["X": left, "Y": top, "Width": width, "Height": height]
    ]
    result[kCGWindowOwnerName as String] = owner
    return result
  }

  private func evidence(_ rows: [[String: Any]], front: Int32?, system: Bool) -> MenuBarEvidence.Result {
    let bar = row(pid: 652, owner: "Window Server", top: 0, height: 33, layer: 24)
    let windows = MenuBarEvidence.windows(from: rows + [bar], ownPID: 42, frontmostPID: front,
                                          primaryScreenHeight: screen.height)
    return MenuBarEvidence.evaluate(frame: screen, visibleFrame: visible, bandFrame: band,
                                    windows: windows, systemFullScreen: system)
  }

  func testOnlyAnOrdinaryWindowOfTheFrontmostProcessIsNativeFullScreen() {
    XCTAssertTrue(evidence([row(pid: 500)], front: 500, system: true).nativeFullScreen)
    // The desktop, the Dock, Show Desktop and the screenshot tool are never a full-screen app.
    for owner in ["Dock", "WindowManager", "Screenshot"] {
      let result = evidence([row(pid: 500, owner: owner)], front: 500, system: true)
      XCTAssertFalse(result.nativeFullScreen, owner)
      XCTAssertEqual(result.context, .desktop, owner)
    }
    XCTAssertFalse(evidence([row(pid: 500, owner: "Finder", layer: -2_147_483_603)], front: 500,
                            system: true).nativeFullScreen)
    // Our own windows, also when this app is in front.
    XCTAssertFalse(evidence([row(pid: 42)], front: 42, system: true).nativeFullScreen)
    // Another process with the same window, and the same window without the system signal.
    XCTAssertFalse(evidence([row(pid: 501)], front: 500, system: true).nativeFullScreen)
    XCTAssertFalse(evidence([row(pid: 500)], front: 500, system: false).nativeFullScreen)
  }

  func testUnusableEvidenceIsNeverNativeFullScreen() {
    func result(frame: CGRect, visibleFrame: CGRect, bandFrame: CGRect,
                windows: [MenuBarEvidence.Window]?) -> MenuBarEvidence.Result {
      MenuBarEvidence.evaluate(frame: frame, visibleFrame: visibleFrame, bandFrame: bandFrame,
                               windows: windows, systemFullScreen: true)
    }
    let window = MenuBarEvidence.Window(owner: .application, layer: 0,
                                        bounds: CGRect(x: 0, y: 0, width: 1512, height: 834),
                                        isFrontmostApp: true)
    XCTAssertTrue(result(frame: screen, visibleFrame: visible, bandFrame: band,
                         windows: [window]).nativeFullScreen)
    let missing = result(frame: screen, visibleFrame: visible, bandFrame: band, windows: nil)
    XCTAssertFalse(missing.nativeFullScreen)
    XCTAssertEqual(missing.context, .unknown)
    for invalid in [CGRect.null, .zero, .infinite, CGRect(x: CGFloat.nan, y: 0, width: 1512, height: 982)] {
      for unknown in [
        result(frame: invalid, visibleFrame: visible, bandFrame: band, windows: [window]),
        result(frame: screen, visibleFrame: invalid, bandFrame: band, windows: [window]),
        result(frame: screen, visibleFrame: visible, bandFrame: invalid, windows: [window])
      ] {
        XCTAssertFalse(unknown.nativeFullScreen, "\(invalid)")
        XCTAssertEqual(unknown.context, .unknown, "\(invalid)")
      }
      let malformed = MenuBarEvidence.Window(owner: .application, layer: 0, bounds: invalid,
                                             isFrontmostApp: true)
      XCTAssertFalse(result(frame: screen, visibleFrame: visible, bandFrame: band,
                            windows: [malformed]).nativeFullScreen, "\(invalid)")
    }
  }

  /// A known limit, written down: public metadata gives a zoomed window with the Dock hidden or
  /// at a side the bounds of a native full-screen window below the camera housing. Only the
  /// system signal tells them apart, and that signal is one for all displays.
  func testKnownLimitAZoomedWindowIsDesktopOnlyWithoutTheSystemSignal() {
    for zoomed in [row(pid: 500, top: 33, height: 949),
                   row(pid: 500, top: 33, height: 949, left: 60, width: 1452)] {
      XCTAssertEqual(evidence([zoomed], front: 500, system: false).context, .desktop)
      XCTAssertEqual(evidence([zoomed], front: 500, system: true).context, .fullScreen)
    }
  }

  /// One random row, and whether an independent reading of its numbers makes it native full
  /// screen for the frontmost process `front`.
  private func randomRow(_ next: (Int) -> Int, front: Int32?) -> (row: [String: Any], native: Bool) {
    let pid: Int32 = [500, 500, 501, 42][next(4)]
    let owner: String? = [nil, "Browser", "Browser", "Dock", "WindowManager", "Finder"][next(6)]
    // Half of the pairs reach the bottom edge of the display, at 982 from the top.
    let (top, height) = [(148, 834), (33, 949), (0, 982), (150, 834), (148, 831), (1130, 834),
                         (33, 0), (-834, 834)][next(8)]
    let (left, width) = [(0, 1512), (60, 1452), (0, 605), (907, 605), (0, 604), (908, 605),
                         (1512, 1512), (0, 0)][next(8)]
    let layer = [0, 0, 0, 0, -1, 1, 24][next(7)]
    let alpha = [0, 0.5, 1, 1][next(4)]
    let ordinary = pid != 42 && owner != "Dock" && owner != "WindowManager"
    let overlap = min(left + width, 1512) - max(left, 0)
    let native = ordinary && pid == front && layer == 0 && alpha > 0 && width > 0 && height > 0
      && abs(top + height - 982) <= 2 && top < 982 && Double(overlap) >= 1512 * 0.4
    return (row(pid: pid, owner: owner, top: top, height: height, left: left, width: width,
                layer: layer, alpha: alpha), native)
  }

  /// Native full screen needs the system signal and a visible layer-zero window of the
  /// frontmost process at the bottom of this display, in any order and with duplicates.
  func testRandomListsAreNativeOnlyWithEveryPieceOfEvidence() {
    var seed: UInt64 = 91
    func next(_ bound: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int((seed >> 33) % UInt64(bound))
    }
    var natives = 0
    for _ in 0..<2000 {
      let front: Int32? = [500, 500, 500, 501, 42, nil][next(6)]
      let system = next(4) != 0
      let sample = (0..<next(8)).map { _ in randomRow(next, front: front) }
      let rows = sample.map(\.row)
      let expected = system && sample.contains { $0.native }
      let result = evidence(rows, front: front, system: system)
      XCTAssertEqual(result.nativeFullScreen, expected, "\(rows) front \(String(describing: front))")
      if expected {
        natives += 1
        XCTAssertEqual(result.context, .fullScreen)
      }
      XCTAssertEqual(evidence(Array(rows.reversed()) + rows, front: front, system: system).nativeFullScreen,
                     expected)
    }
    XCTAssertGreaterThan(natives, 50, "the generator must reach the positive case")
  }
}
