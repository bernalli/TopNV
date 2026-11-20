import XCTest
@testable import TopNVCore

final class NativeFullScreenTests: XCTestCase {
  private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let menuBar = CGRect(x: 0, y: 949, width: 1512, height: 33)
  private let desktop = CGRect(x: 0, y: 0, width: 1512, height: 949)
  private let browserPID: Int32 = 81452

  private func row(_ top: Int, _ height: Int, left: Int = 0, width: Int = 1512,
                   layer: Int = 0, alpha: Double = 1) -> [String: Any] {
    [kCGWindowOwnerPID as String: browserPID, kCGWindowLayer as String: layer,
     kCGWindowAlpha as String: alpha,
     kCGWindowBounds as String: ["X": left, "Y": top, "Width": width, "Height": height]]
  }

  // Quartz bounds from the three Brave surfaces on the notched display.
  private var browser: [[String: Any]] { [row(33, 40), row(73, 75), row(148, 834)] }

  private func sample(_ rows: [[String: Any]], front: Int32?, fullScreen: Bool) -> MenuBarEvidence.Result {
    var bar = row(0, 33, layer: 24)
    bar[kCGWindowOwnerName as String] = "Window Server"
    bar[kCGWindowOwnerPID as String] = 652
    let windows = MenuBarEvidence.windows(from: rows + [bar], ownPID: 42, frontmostPID: front,
                                          primaryScreenHeight: screen.height)
    return MenuBarEvidence.evaluate(frame: screen, visibleFrame: desktop, bandFrame: menuBar,
                                    windows: windows, systemFullScreen: fullScreen)
  }

  private func update(_ state: inout KeyedOverlayState, _ evidence: MenuBarEvidence.Result,
                      active: [Int], now: Double = 1) -> KeyedOverlayState.Decision {
    state.update(.init(activeWindowIDs: active, appearance: .light, context: evidence.context,
                       menuVisible: evidence.menuVisible, enabled: true, now: now,
                       nativeFullScreen: evidence.nativeFullScreen))
  }

  func testMeasuredBrowserInNativeFullScreenClosesOnlyActiveWindowsAndNeverCreates() {
    let evidence = sample(browser, front: browserPID, fullScreen: true)
    XCTAssertTrue(evidence.menuVisible)
    XCTAssertEqual(evidence.context, .fullScreen)
    var state = KeyedOverlayState()
    let ordinary = sample([], front: browserPID, fullScreen: false)
    _ = update(&state, ordinary, active: [7])
    _ = update(&state, ordinary, active: [8])
    let decision = update(&state, evidence, active: [9, 8, 8])
    XCTAssertEqual(decision.close.sorted(), [8, 9])
    XCTAssertEqual(state.visibility, [7: true])
    XCTAssertTrue(decision.gates.isEmpty)
    XCTAssertNil(update(&state, evidence, active: []).create)
  }

  func testMissingOrDifferentFrontmostProcessAndZoomedDesktopStayDesktop() {
    for front: Int32? in [nil, 123, 0, -1] {
      XCTAssertEqual(sample(browser, front: front, fullScreen: true).context, .desktop)
    }
    for rows in [browser, [row(33, 949)]] {
      let evidence = sample(rows, front: browserPID, fullScreen: false)
      XCTAssertEqual(evidence.context, .desktop)
      var state = KeyedOverlayState()
      XCTAssertNotNil(update(&state, evidence, active: []).create)
    }
  }

  func testOnlyAVisibleLayerZeroWindowAtThisDisplaysBottomQualifies() {
    for window in [row(148, 834, left: 1512), row(1130, 834), row(-834, 834),
                   row(148, 831), row(148, 834, width: 604), row(148, 834, layer: 1),
                   row(148, 834, alpha: 0)] {
      XCTAssertEqual(sample([window], front: browserPID, fullScreen: true).context, .desktop)
    }
    XCTAssertEqual(sample([row(148, 834, width: 605)], front: browserPID, fullScreen: true).context,
                   .fullScreen)
  }

  func testCoveringDesktopWindowOnlyHidesTheGateAndKeepsTheBudget() {
    let covered = sample([row(0, 982)], front: browserPID, fullScreen: false)
    XCTAssertEqual(covered.context, .fullScreen)
    var state = KeyedOverlayState()
    let ordinary = sample([], front: browserPID, fullScreen: false)
    for _ in 0..<4 {
      let hidden = update(&state, covered, active: [7])
      XCTAssertEqual(hidden.close, [])
      XCTAssertEqual(hidden.gates, [7: false])
      XCTAssertEqual(update(&state, ordinary, active: [7]).gates, [7: true])
    }
    XCTAssertEqual(state.creationsThisVisit, 0)
  }

  func testNativeFullScreenClosesAfterSpaceMembershipSettles() {
    let evidence = sample(browser, front: browserPID, fullScreen: true)
    var state = KeyedOverlayState()
    state.spaceDidChange(now: 1)
    XCTAssertTrue(update(&state, evidence, active: [7]).close.isEmpty)
    XCTAssertEqual(update(&state, evidence, active: [8], now: 1.6).close, [8])
  }

  func testMalformedOwnerPIDCannotMatchTheFrontmostProcess() {
    let invalid: [Any?] = [nil, true, "81452", 81452.5, Int64(4_294_967_296) + Int64(browserPID), NSNull()]
    for value in invalid {
      var broken = row(148, 834)
      broken[kCGWindowOwnerPID as String] = value
      let evidence = sample(browser + [broken], front: browserPID, fullScreen: true)
      XCTAssertEqual(evidence.context, .unknown)
      XCTAssertFalse(evidence.nativeFullScreen)
    }
  }

  func testRandomWindowListsPreserveTheSignalUnderReorderingAndDuplication() {
    var seed: UInt64 = 57
    func next(_ bound: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1
      return Int((seed >> 32) % UInt64(bound))
    }
    let candidates = browser + [row(148, 834, left: 1512), row(148, 834, layer: 1), row(148, 834, alpha: 0)]
    for _ in 0..<500 {
      let rows = (0..<next(10)).map { _ in candidates[next(candidates.count)] }
      let system = next(2) == 0
      let front = next(2) == 0 ? browserPID : nil
      let original = sample(rows, front: front, fullScreen: system)
      let reordered = sample(Array(rows.reversed()) + rows, front: front, fullScreen: system)
      XCTAssertEqual(reordered.nativeFullScreen, original.nativeFullScreen)
      XCTAssertEqual(reordered.context, original.context)
    }
  }
}
