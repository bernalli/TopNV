import XCTest
@testable import TopNVCore

/// A Space switch slides the windows bound to a Space sideways. The notification comes only when
/// the slide ends, so the samples of the slide mix two Spaces and must not decide a gate.
/// The numbers are the samples of 19-11 (desktop to a full-screen Space and back), in points.
final class SpaceSlidingTests: XCTestCase {
  typealias State = KeyedOverlayState
  typealias Window = MenuBarEvidence.Window

  private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let visible = CGRect(x: 60, y: 0, width: 1452, height: 949)
  private let strip = CGRect(x: 0, y: 949, width: 1512, height: 33)
  private let desktopLayer = -2_147_483_624
  private let fullScreenBackdropLayer = -2_147_483_622

  // MARK: - Helpers

  private func input(
    active: [Int] = [], appearance: State.Appearance = .light, context: State.Context = .desktop,
    menu: Bool = true, enabled: Bool = true, time: Double = 10, sliding: Bool = false
  ) -> State.Input {
    .init(activeWindowIDs: active, appearance: appearance, context: context, menuVisible: menu,
          enabled: enabled, now: time, spaceSliding: sliding)
  }

  private func desktop(_ x: CGFloat, layer: Int? = nil, size: CGSize? = nil, y: CGFloat = 0,
                       alpha: Double = 1) -> Window {
    .init(owner: .desktop, layer: layer ?? desktopLayer,
          bounds: CGRect(origin: CGPoint(x: x, y: y), size: size ?? frame.size),
          isWindowManager: true, alpha: alpha)
  }

  private func keyed(_ x: CGFloat, alpha: Double = 1) -> Window {
    .init(owner: .ownApp, layer: MenuBarEvidence.overlayLevel, bounds: strip.offsetBy(dx: x, dy: 0),
          alpha: alpha)
  }

  private func bar(_ x: CGFloat) -> Window {
    .init(owner: .windowServer, layer: 24, bounds: strip.offsetBy(dx: x, dy: 0))
  }

  private var dock: Window { .init(owner: .desktop, layer: 20, bounds: frame) }

  private func evaluate(_ windows: [Window]?) -> MenuBarEvidence.Result {
    MenuBarEvidence.evaluate(frame: frame, visibleFrame: visible, bandFrame: strip, windows: windows)
  }

  /// One sample of a slide: the desktop that leaves at `leaving`, the full-screen Space that
  /// arrives at `arriving`, each with its menu bar and its keyed window.
  private func slide(leaving: CGFloat, arriving: CGFloat) -> [Window] {
    [dock, desktop(leaving), bar(leaving), keyed(leaving),
     desktop(arriving), desktop(arriving, layer: fullScreenBackdropLayer), bar(arriving),
     keyed(arriving, alpha: 0)]
  }

  private func entry(owner: Any? = "WindowManager", pid: Any? = Int32(600),
                     layer: Any? = -2_147_483_624, alpha: Any? = 1,
                     bounds: Any? = ["X": -155, "Y": 0, "Width": 1512, "Height": 982]) -> [String: Any] {
    var result: [String: Any] = ["kCGWindowNumber": 77, "extra": "ignored"]
    result[kCGWindowOwnerName as String] = owner
    result[kCGWindowOwnerPID as String] = pid
    result[kCGWindowLayer as String] = layer
    result[kCGWindowAlpha as String] = alpha
    result[kCGWindowBounds as String] = bounds
    return result
  }

  private func parse(_ list: [[String: Any]]) -> [Window]? {
    MenuBarEvidence.windows(from: list, ownPID: 42, primaryScreenHeight: 982)
  }

  // MARK: - Evidence, measured samples

  func testTheMeasuredSlideIsRecognisedAndHasNoMenuBarInPlace() {
    for (leaving, arriving) in [(-24, 1552), (-155, 1421), (-579, 997), (-1326, 250), (-1571, 5),
                                (-1573, 3)] as [(CGFloat, CGFloat)] {
      for windows in [slide(leaving: leaving, arriving: arriving),
                      slide(leaving: arriving, arriving: leaving)] {
        let result = evaluate(windows)
        XCTAssertTrue(result.spaceSliding, "\(leaving) \(arriving)")
        XCTAssertFalse(result.menuVisible, "\(leaving) \(arriving)")
        XCTAssertEqual(result.context, .desktop)
      }
    }
  }

  func testAtRestAndInTheLastPointsNothingSlides() {
    let rest = evaluate([dock, desktop(0), bar(0), keyed(0)])
    XCTAssertFalse(rest.spaceSliding)
    XCTAssertTrue(rest.menuVisible)
    // 08:59:08.408 and 08:59:10.231: the arriving Space is within the tolerance of its place.
    for (leaving, arriving) in [(-1574, 2), (1574, -2), (-1575, 1), (1576, 0)] as [(CGFloat, CGFloat)] {
      let result = evaluate(slide(leaving: leaving, arriving: arriving))
      XCTAssertFalse(result.spaceSliding, "\(leaving) \(arriving)")
      XCTAssertTrue(result.menuVisible, "\(leaving) \(arriving)")
    }
  }

  func testTheWindowListDictionariesOfASlideAreRecognised() throws {
    let list = [
      entry(owner: "Dock", layer: 20, bounds: ["X": 0, "Y": 0, "Width": 1512, "Height": 982]),
      entry(owner: "Screenshot", layer: 24, bounds: ["X": 0, "Y": 0, "Width": 1512, "Height": 982]),
      entry(owner: "Terminale", pid: Int32(700), layer: 0,
            bounds: ["X": -95, "Y": 33, "Width": 1452, "Height": 949]),
      entry(owner: "TopNV", pid: Int32(42), layer: 26, alpha: 0,
            bounds: ["X": 1421, "Y": 0, "Width": 1512, "Height": 33]),
      entry(owner: "TopNV", pid: Int32(42), layer: 26,
            bounds: ["X": -155, "Y": 0, "Width": 1512, "Height": 33]),
      entry(layer: -2_147_483_622, bounds: ["X": 1421, "Y": 0, "Width": 1512, "Height": 982]),
      entry(), entry(bounds: ["X": 1421, "Y": 0, "Width": 1512, "Height": 982]),
    ]
    let result = evaluate(try XCTUnwrap(parse(list)))
    XCTAssertTrue(result.spaceSliding)
    XCTAssertFalse(result.menuVisible)
    XCTAssertEqual(result.context, .desktop)
  }

  func testOneDisplacedSpaceWindowIsEnough() {
    // A rebound at the last Space, or a system without the WindowManager desktop window.
    XCTAssertTrue(evaluate([desktop(40), bar(40)]).spaceSliding)
    XCTAssertTrue(evaluate([desktop(-700), bar(0)]).spaceSliding)
    XCTAssertTrue(evaluate([keyed(-300), bar(0)]).spaceSliding)
    XCTAssertTrue(evaluate([keyed(300, alpha: 0), bar(0)]).spaceSliding)
    XCTAssertTrue(evaluate([desktop(-300, layer: fullScreenBackdropLayer)]).spaceSliding)
  }

  // MARK: - Evidence, what is not a slide

  func testDisplacedWindowsOfOthersAreNotASlide() {
    let moved = frame.offsetBy(dx: -300, dy: 0)
    let others: [Window] = [
      .init(owner: .application, layer: 0, bounds: moved),
      .init(owner: .application, layer: 26, bounds: strip.offsetBy(dx: -300, dy: 0)),
      .init(owner: .desktop, layer: 20, bounds: moved),
      .init(owner: .desktop, layer: -2_147_483_603, bounds: moved),
      .init(owner: .windowServer, layer: 24, bounds: strip.offsetBy(dx: -300, dy: 0)),
      .init(owner: .windowServer, layer: -2_147_483_626, bounds: moved),
      desktop(-300, layer: 0), desktop(-300, layer: 18),
      .init(owner: .ownApp, layer: 100, bounds: strip.offsetBy(dx: -300, dy: 0)),
      .init(owner: .ownApp, layer: -2_147_483_622, bounds: strip.offsetBy(dx: -300, dy: 0)),
      .init(owner: .ownApp, layer: 26, bounds: CGRect(x: -3, y: 967, width: 15, height: 15)),
    ]
    for window in others {
      XCTAssertFalse(evaluate([window, bar(0)]).spaceSliding, "\(window.owner) \(window.layer)")
    }
  }

  func testNeighbourDisplaysThumbnailsAndOtherSizesAreNotASlide() {
    let still: [Window] = [
      desktop(1512), desktop(-1512), desktop(1576), desktop(-1574), desktop(3024),
      desktop(2), desktop(-2), desktop(0),
      desktop(300, size: CGSize(width: 302, height: 196), y: 700),
      desktop(300, y: 40), desktop(300, y: -982), desktop(300, y: 982),
      desktop(300, size: CGSize(width: 1800, height: 1169)),
      desktop(300, size: CGSize(width: 1512, height: 949)),
      desktop(300, size: CGSize(width: 1509, height: 982)),
      keyed(1512), keyed(-1575), keyed(2),
    ]
    for window in still {
      XCTAssertFalse(evaluate([window, bar(0)]).spaceSliding, "\(window.bounds)")
    }
  }

  func testUnusableEvidenceIsNeverASlide() {
    XCTAssertFalse(evaluate(nil).spaceSliding)
    XCTAssertFalse(evaluate([]).spaceSliding)
    let windows = slide(leaving: -155, arriving: 1421)
    for band in [CGRect.null, .infinite, .zero, strip.offsetBy(dx: 0, dy: 100)] {
      XCTAssertFalse(MenuBarEvidence.evaluate(frame: frame, visibleFrame: visible, bandFrame: band,
                                              windows: windows).spaceSliding)
    }
    for screen in [CGRect.null, .infinite, .zero] {
      XCTAssertFalse(MenuBarEvidence.evaluate(frame: screen, visibleFrame: visible, bandFrame: strip,
                                              windows: windows).spaceSliding)
    }
  }

  /// Wrong types, missing fields, truncated bounds and values out of range in any entry make the
  /// whole list unavailable: a malformed list is never evidence of a slide. Extra fields are ignored.
  func testAMalformedEntryNeverCountsAsASlide() throws {
    let good = entry()
    XCTAssertTrue(evaluate(try XCTUnwrap(parse([good]))).spaceSliding)
    var extra = good
    extra["kCGWindowName"] = "never read"
    extra["kCGWindowMemoryUsage"] = 1
    XCTAssertTrue(evaluate(try XCTUnwrap(parse([extra]))).spaceSliding)

    let numbers: [Any] = ["12", NSNull(), true, [1], Double.nan, Double.infinity, -Double.infinity]
    var malformed: [[String: Any]] = [
      entry(pid: nil), entry(layer: nil), entry(alpha: nil), entry(bounds: nil),
      entry(owner: 7), entry(owner: NSNull()), entry(pid: Int32(0)), entry(pid: Int32(-5)),
      entry(layer: 0.5), entry(alpha: 1.5), entry(alpha: -0.1), entry(bounds: "0,0,1512,982"),
      entry(bounds: [:] as [String: Any]),
      entry(bounds: ["X": -155, "Y": 0, "Width": 1512]),
      entry(bounds: ["X": -155, "Y": 0, "Width": -1512, "Height": 982]),
      entry(bounds: ["X": -155, "Y": 0, "Width": 1512, "Height": -982]),
      entry(bounds: ["X": -155, "Y": Double.greatestFiniteMagnitude, "Width": 1512,
                     "Height": Double.greatestFiniteMagnitude]),
    ]
    for value in numbers {
      malformed += [entry(pid: value), entry(layer: value), entry(alpha: value)]
      for key in ["X", "Y", "Width", "Height"] {
        var bounds: [String: Any] = ["X": -155, "Y": 0, "Width": 1512, "Height": 982]
        bounds[key] = value
        malformed.append(entry(bounds: bounds))
      }
    }
    for bad in malformed {
      for list in [[bad], [good, bad], [bad, good], [good, bad, good]] {
        XCTAssertNil(parse(list), "\(bad)")
        XCTAssertFalse(evaluate(parse(list)).spaceSliding, "\(bad)")
      }
    }
    // In range for the parser, far out of range for a display: no slide, no trap.
    for x in [1e300, -1e300, 1e12, -1e12] {
      let far = entry(bounds: ["X": x, "Y": 0, "Width": 1512, "Height": 982])
      XCTAssertFalse(evaluate(try XCTUnwrap(parse([far]))).spaceSliding, "\(x)")
    }
    let empty = entry(bounds: ["X": -155, "Y": 0, "Width": 0, "Height": 0])
    XCTAssertFalse(evaluate(try XCTUnwrap(parse([empty]))).spaceSliding)
  }

  /// The result is the same for any order and any number of copies, and windows that are not
  /// evidence never hide a window that is.
  func testSlidingIsInvariantUnderDuplicatesOrderingAndNoise() {
    var seed: UInt64 = 0x2545_F491_4F6C_DD1D
    func next(_ bound: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int((seed >> 33) % UInt64(bound))
    }
    func noise() -> Window {
      let owner = [MenuBarEvidence.Owner.windowServer, .desktop, .application][next(3)]
      let bounds = CGRect(x: CGFloat(next(4000) - 2000), y: CGFloat(next(1200) - 100),
                          width: CGFloat(next(1600) + 1), height: CGFloat(next(1000) + 1))
      return .init(owner: owner, layer: [0, 3, 18, 20, 24, 25, 100, -2_147_483_603][next(8)],
                   bounds: bounds, alpha: Double(next(3)) / 2)
    }
    let evidence: [Window] = [desktop(-155), desktop(997), desktop(40), keyed(-579), keyed(250, alpha: 0),
                              desktop(700, layer: fullScreenBackdropLayer)]
    let still: [Window] = [desktop(0), desktop(1512), desktop(-1576), keyed(0), keyed(1576), desktop(2)]
    for _ in 0..<400 {
      var windows = (0..<next(12)).map { _ in noise() } + (0..<next(4)).map { _ in still[next(still.count)] }
      XCTAssertFalse(evaluate(windows).spaceSliding)
      let chosen = evidence[next(evidence.count)]
      windows.insert(chosen, at: next(windows.count + 1))
      XCTAssertTrue(evaluate(windows).spaceSliding)
      var shuffled = windows + windows.filter { _ in next(2) == 0 }
      for index in shuffled.indices { shuffled.swapAt(index, next(shuffled.count)) }
      XCTAssertTrue(evaluate(shuffled).spaceSliding)
      XCTAssertEqual(evaluate(shuffled).menuVisible, evaluate(windows).menuVisible)
      XCTAssertEqual(evaluate(shuffled).context, evaluate(windows).context)
    }
  }

  // MARK: - State

  func testASlideKeepsTheGateOfTheWindowThatLeaves() {
    for appearance in [State.Appearance.light, .dark, .unknown] {
      for context in [State.Context.desktop, .fullScreen, .unknown] {
        var state = State()
        _ = state.update(input(active: [1], time: 10))
        for step in 0..<9 {
          let result = state.update(input(active: [1], appearance: appearance, context: context,
                                          menu: false, time: 20 + 0.1 * Double(step), sliding: true))
          XCTAssertEqual(result.gates, [:])
          XCTAssertNil(result.create)
          XCTAssertNil(result.keyChange)
        }
        XCTAssertEqual(state.visibility, [1: true])
      }
    }
  }

  func testAStableMissingMenuBarDarkBarOrFullScreenStillHidesAtOnce() {
    let hiding: [State.Input] = [
      input(active: [1], menu: false, time: 20), input(active: [1], appearance: .dark, time: 20),
      input(active: [1], appearance: .unknown, time: 20),
      input(active: [1], context: .fullScreen, time: 20), input(active: [1], context: .unknown, time: 20),
      input(active: [1], enabled: false, time: 20),
    ]
    for sample in hiding {
      var state = State()
      _ = state.update(input(active: [1], time: 10))
      XCTAssertEqual(state.update(sample).gates, [1: false])
    }
  }

  /// 08:59:10.3: the window of the arriving Space is active before the notification, and the
  /// appearance probe still belongs to the Space that left.
  func testArrivalAfterASlideIgnoresTheStaleProbeBeforeTheNotification() {
    var state = State()
    _ = state.update(input(active: [1], time: 10))
    state.spaceDidChange(now: 11)
    _ = state.update(input(active: [2], appearance: .dark, time: 12))
    XCTAssertEqual(state.visibility, [1: true, 2: false])
    for step in 0..<9 {
      _ = state.update(input(active: [2], appearance: .dark, menu: false,
                             time: 20 + 0.1 * Double(step), sliding: true))
    }
    XCTAssertEqual(state.update(input(active: [1], appearance: .dark, time: 20.9)).gates, [:])
    state.spaceDidChange(now: 20.92)
    XCTAssertEqual(state.update(input(active: [1], time: 21.0)).gates, [:])
    XCTAssertEqual(state.update(input(active: [1], time: 21.5)).gates, [1: true])
    XCTAssertEqual(state.visibility, [1: true, 2: false])
  }

  /// The same race towards a dark or full-screen Space: a stale light probe must neither show
  /// its hidden window nor create one there.
  func testArrivalOnADarkSpaceNeitherShowsNorCreatesFromTheStaleLightProbe() {
    for existing in [[2], []] as [[Int]] {
      var state = State()
      if !existing.isEmpty {
        _ = state.update(input(active: existing, appearance: .dark, time: 1))
        state.spaceDidChange(now: 2)
      }
      _ = state.update(input(active: [1], time: 10))
      for step in 0..<9 {
        _ = state.update(input(active: [1], menu: false, time: 20 + 0.1 * Double(step), sliding: true))
      }
      let stale = state.update(input(active: existing, time: 20.9))
      XCTAssertEqual(stale.gates, [:])
      XCTAssertNil(stale.create)
      state.spaceDidChange(now: 20.92)
      XCTAssertNil(state.update(input(active: existing, time: 21.0)).create)
      let settled = state.update(input(active: existing, appearance: .dark, time: 21.5))
      XCTAssertNil(settled.create)
      XCTAssertEqual(settled.gates, existing.isEmpty ? [:] : [2: false])
      XCTAssertEqual(state.visibility[1], true)
    }
  }

  func testAnEndlessSlideStopsPostponingTheDecision() throws {
    var state = State()
    _ = state.update(input(active: [1], time: 10))
    var hiddenAt: Double?
    for step in 0..<100 {
      let time = 20 + 0.1 * Double(step)
      let result = state.update(input(active: [1], menu: false, time: time, sliding: true))
      if result.gates[1] == false, hiddenAt == nil { hiddenAt = time }
    }
    XCTAssertEqual(try XCTUnwrap(hiddenAt), 23.5, accuracy: 0.11)
    XCTAssertEqual(state.visibility, [1: false])
  }

  func testAFlickeringSlideSignalIsBoundedToo() throws {
    for period in [2, 3, 5] {
      var state = State()
      _ = state.update(input(active: [1], time: 10))
      var hiddenAt: Double?
      for step in 0..<100 {
        let time = 20 + 0.1 * Double(step)
        let result = state.update(input(active: [1], menu: false, time: time,
                                        sliding: step % period == 0))
        if result.gates[1] == false, hiddenAt == nil { hiddenAt = time }
      }
      XCTAssertLessThanOrEqual(try XCTUnwrap(hiddenAt), 23.71, "period \(period)")
    }
  }

  func testASampleWithoutEvidenceInTheMiddleOfASlideDoesNotDecide() {
    var state = State()
    _ = state.update(input(active: [1], time: 10))
    for step in 0..<9 {
      // One sample in three has no list, no appearance and no slide.
      let dropout = step % 3 == 1
      let result = state.update(input(active: [1], appearance: dropout ? .unknown : .light,
                                      context: dropout ? .unknown : .desktop, menu: false,
                                      time: 20 + 0.1 * Double(step), sliding: !dropout))
      XCTAssertEqual(result.gates, [:])
    }
    XCTAssertEqual(state.visibility, [1: true])
  }

  /// Quick switches back and forth: every notified slide has the whole protection, however
  /// short the rest between two slides.
  func testConsecutiveNotifiedSlidesAreEachProtected() {
    var state = State()
    _ = state.update(input(active: [1], time: 10))
    state.spaceDidChange(now: 11)
    _ = state.update(input(active: [2], time: 12))
    var time = 20.0
    for swipe in 0..<12 {
      let leaving = swipe % 2 == 0 ? 2 : 1
      for _ in 0..<9 {
        XCTAssertEqual(state.update(input(active: [leaving], menu: false, time: time, sliding: true)).gates,
                       [:], "swipe \(swipe)")
        time += 0.1
      }
      state.spaceDidChange(now: time)
      XCTAssertEqual(state.update(input(active: [3 - leaving], time: time + 0.1)).gates, [:])
      time += 0.2
    }
    XCTAssertEqual(state.visibility, [1: true, 2: true])
  }

  func testAHalfSwipeReleasedBackKeepsTheWindowAndTheBudget() {
    var state = State()
    _ = state.update(input(active: [1], time: 10))
    for step in 0..<10 {
      _ = state.update(input(active: [1], menu: false, time: 20 + 0.1 * Double(step), sliding: true))
    }
    XCTAssertEqual(state.update(input(active: [1], time: 21.0)).gates, [:])
    XCTAssertEqual(state.update(input(active: [1], time: 21.5)).gates, [1: true])
    XCTAssertEqual(state.visibility, [1: true])
    XCTAssertEqual(state.creationsThisVisit, 0)
  }

  func testSlidingAloneNeverRefillsTheVisitBudget() throws {
    var state = State()
    for attempt in 0..<3 {
      let request = try XCTUnwrap(state.update(input(time: Double(attempt * 10 + 10))).create)
      XCTAssertTrue(state.commit(request, windowID: attempt + 1))
    }
    for step in 0..<200 {
      XCTAssertNil(state.update(input(time: 50 + 0.1 * Double(step), sliding: step % 20 < 9)).create)
    }
    XCTAssertEqual(state.creationsThisVisit, 3)
  }

  func testNonFiniteOrBackwardTimeWhileSlidingNeverFreezesTheGate() {
    for bad in [Double.nan, .infinity, -.infinity, -1, 0, 19.99] {
      var state = State()
      _ = state.update(input(active: [1], time: 10))
      _ = state.update(input(active: [1], menu: false, time: bad, sliding: true))
      _ = state.update(input(active: [1], menu: false, time: 20, sliding: true))
      var hidden = false
      for step in 1..<60 where state.update(input(active: [1], menu: false,
                                                  time: 20 + 0.1 * Double(step))).gates[1] == false {
        hidden = true
      }
      XCTAssertTrue(hidden, "\(bad)")
    }
  }

  /// Duplicates are closed during a slide as during the settling time.
  func testDuplicatesAreClosedAlsoDuringASlide() {
    var state = State()
    _ = state.update(input(active: [1], time: 10))
    let result = state.update(input(active: [3, 1, 2, 3], menu: false, time: 20, sliding: true))
    XCTAssertEqual(result.close, [2, 3])
    XCTAssertEqual(result.gates, [:])
  }

  /// For any order of samples, notifications, membership changes and slide signals: in the half
  /// second after a sliding sample nothing is gated or created while the slide is younger than
  /// three seconds, a gate never names a window that is not the keeper, a window is shown and
  /// created only on full positive evidence, and the visit budget holds.
  func testRandomSlidesKeepTheInvariants() {
    var seed: UInt64 = 0xD1B5_4A32_D192_ED03
    func next(_ bound: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int((seed >> 33) % UInt64(bound))
    }
    for _ in 0..<300 {
      var state = State()
      var now = 1.0
      var known: [Int] = []
      var nextID = 1
      var createdSinceNotification = 0
      var slideStart: Double?
      var frozenUntil = 0.0
      for _ in 0..<150 {
        now += [0.01, 0.05, 0.1, 0.1, 0.3, 0.7][next(6)]
        if next(6) == 0 {
          state.spaceDidChange(now: now)
          createdSinceNotification = 0
          frozenUntil = now + 0.5
          slideStart = nil
          continue
        }
        var active = known.filter { _ in next(3) == 0 }
        if next(8) == 0, let first = active.first { active.append(first) }
        active.reverse()
        let appearance = [State.Appearance.light, .light, .light, .dark, .unknown][next(5)]
        let context = [State.Context.desktop, .desktop, .desktop, .fullScreen, .unknown][next(5)]
        let menu = next(4) != 0
        let enabled = next(12) != 0
        let sliding = next(3) == 0
        let allPositive = appearance == .light && context == .desktop && menu && enabled
        if sliding {
          let start = slideStart ?? now
          slideStart = start
          if now - start <= 3 { frozenUntil = max(frozenUntil, now + 0.5) }
        } else if now >= frozenUntil {
          slideStart = nil
        }
        let result = state.update(.init(
          activeWindowIDs: active, appearance: appearance, context: context, menuVisible: menu,
          enabled: enabled, now: now, spaceSliding: sliding))
        let distinct = Set(active).sorted()
        XCTAssertEqual(result.close, Array(distinct.dropFirst()))
        XCTAssertTrue(result.gates.keys.allSatisfy { $0 == distinct.first })
        for (_, shown) in result.gates where shown { XCTAssertTrue(allPositive) }
        if now < frozenUntil {
          XCTAssertTrue(result.gates.isEmpty)
          XCTAssertNil(result.create)
          XCTAssertNil(result.keyChange)
        } else if let keeper = distinct.first {
          XCTAssertEqual(result.gates, [keeper: allPositive])
        }
        if let request = result.create {
          XCTAssertTrue(distinct.isEmpty)
          XCTAssertTrue(allPositive)
          createdSinceNotification += 1
          XCTAssertLessThanOrEqual(createdSinceNotification, 3)
          if next(5) != 0, state.commit(request, windowID: nextID) {
            known.append(nextID)
            nextID += 1
          }
        }
        if next(15) == 0, let victim = known.first {
          state.forget(victim)
          known.removeFirst()
        }
      }
    }
  }

  // MARK: - Evidence and state together, measured sequence

  /// 08:59:07–10: desktop (window 1, shown) to the full-screen Space (window 2, hidden) and back,
  /// with the appearance probe late at both arrivals. Neither gate changes.
  func testTheMeasuredSwipeAndReturnChangeNoGate() {
    var state = State()
    func step(_ windows: [Window], active: Int, _ appearance: State.Appearance, _ time: Double)
      -> State.Decision {
      let evidence = evaluate(windows)
      return state.update(.init(
        activeWindowIDs: [active], appearance: appearance, context: evidence.context,
        menuVisible: evidence.menuVisible, enabled: true, now: time,
        desktopRevealed: evidence.desktopRevealed, spaceSliding: evidence.spaceSliding))
    }
    let onDesktop = [dock, desktop(0), bar(0), keyed(0)]
    let onFullScreen = [desktop(0), desktop(0, layer: fullScreenBackdropLayer), bar(0), keyed(0, alpha: 0)]
    _ = step(onFullScreen, active: 2, .dark, 1)
    state.spaceDidChange(now: 2)
    _ = step(onDesktop, active: 1, .light, 4.848)
    XCTAssertEqual(state.visibility, [1: true, 2: false])

    var decisions: [State.Decision] = []
    for (time, x) in [(7.608, -200), (7.708, -940), (7.808, -1300), (8.108, -1552), (8.308, -1571)]
      as [(Double, CGFloat)] {
      decisions.append(step(slide(leaving: x, arriving: x + 1576), active: 1, .light, time))
    }
    // The bar is back in place; then the full-screen Space is active with a stale light probe.
    decisions.append(step(slide(leaving: -1574, arriving: 2), active: 1, .light, 8.409))
    decisions.append(step(onFullScreen, active: 2, .light, 8.509))
    state.spaceDidChange(now: 8.53)
    decisions.append(step(onFullScreen, active: 2, .dark, 8.609))
    for (time, x) in [(9.312, 43), (9.712, 1463), (10.112, 1571)] as [(Double, CGFloat)] {
      decisions.append(step(slide(leaving: x - 1576, arriving: x), active: 2, .dark, time))
    }
    // The desktop is active again and the probe still says dark.
    decisions.append(step(slide(leaving: -1, arriving: 1575), active: 1, .dark, 10.308))
    decisions.append(step(onDesktop, active: 1, .dark, 10.32))
    state.spaceDidChange(now: 10.33)
    decisions.append(step(onDesktop, active: 1, .light, 10.349))
    for decision in decisions {
      XCTAssertEqual(decision.gates, [:])
      XCTAssertNil(decision.create)
    }
    XCTAssertEqual(step(onDesktop, active: 1, .light, 10.908).gates, [1: true])
    XCTAssertEqual(state.visibility, [1: true, 2: false])
  }
}
