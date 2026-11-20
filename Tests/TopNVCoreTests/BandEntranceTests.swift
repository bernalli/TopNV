import CoreGraphics
import XCTest
@testable import TopNVCore

final class BandEntranceTests: XCTestCase {
  private var state = BandEntrance()
  private let display: UInt32 = 1

  @discardableResult
  private func step(_ sample: BandEntrance.Sample?, enabled: Bool = true,
                    event: BandEntrance.Event = .sample, reduced: Bool = false) -> BandEntrance.Action? {
    state.update(event, enabled: enabled, samples: sample.map { [display: $0] } ?? [:],
                 reduceMotion: reduced)[display]
  }

  func testLaunchAndRealOffToOnEdgesAnimateOnce() {
    XCTAssertEqual(step(.desktop, event: .settings), .start)
    XCTAssertNil(step(.desktop, event: .settings))
    XCTAssertNil(step(.desktop))
    XCTAssertEqual(step(.desktop, enabled: false, event: .settings), .restore)
    XCTAssertEqual(step(.desktop, event: .settings), .start)
  }

  func testRevealInterruptsThenOnlyAnOrdinaryReturnAnimates() {
    XCTAssertEqual(step(.desktop, event: .settings), .start)
    XCTAssertEqual(step(.revealed), .restore)
    _ = step(.revealed)
    XCTAssertEqual(step(.desktop), .start)
    XCTAssertNil(step(.desktop))
  }

  func testInvalidEvidenceOrSystemChangeDisarmsEvenRepeatedReveal() {
    for event in [BandEntrance.Event.system, .sample] {
      state = BandEntrance()
      _ = step(.revealed, event: .settings)
      _ = step(event == .system ? .revealed : .unavailable, event: event)
      _ = step(.revealed)
      XCTAssertNotEqual(step(.desktop), .start)
      _ = step(.revealed)
      XCTAssertEqual(step(.desktop), .start)
    }
  }

  func testSpaceSlideFullScreenAndMissingDisplayRestoreMidwayWithoutReplay() {
    for sample in [BandEntrance.Sample.unavailable, nil, .desktop] {
      state = BandEntrance()
      XCTAssertEqual(step(.desktop, event: .settings), .start)
      XCTAssertEqual(step(sample, event: sample == .desktop ? .system : .sample), .restore)
      XCTAssertNotEqual(step(.desktop), .start)
    }
  }

  func testReduceMotionConsumesEachEntranceAndRestoresInFlight() {
    XCTAssertNotEqual(step(.desktop, event: .settings, reduced: true), .start)
    XCTAssertNil(step(.desktop))
    _ = step(.revealed)
    XCTAssertEqual(step(.desktop), .start)
    XCTAssertEqual(step(.desktop, reduced: true), .restore)
    _ = step(.revealed)
    XCTAssertNotEqual(step(.desktop, reduced: true), .start)
    XCTAssertNil(step(.desktop))
  }

  func testDisplayJoiningOrRecreatedAfterSettlingDoesNotAnimate() {
    _ = step(nil, event: .settings)
    XCTAssertNotEqual(step(.desktop, event: .system), .start)
    XCTAssertNil(step(.desktop))
    _ = step(nil)
    XCTAssertNil(step(.desktop))
  }

  private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let band = CGRect(x: 0, y: 949, width: 1512, height: 33)

  private func desktop(layer: Int = -2_147_483_624, offset: CGFloat = 0) -> MenuBarEvidence.Window {
    .init(owner: .desktop, layer: layer, bounds: frame.offsetBy(dx: offset, dy: 0), isWindowManager: true)
  }

  private func autoHiddenEvidence(_ windows: [MenuBarEvidence.Window]?,
                                  systemFullScreen: Bool = false,
                                  displayFrames: [CGRect] = []) -> MenuBarEvidence.Result {
    MenuBarEvidence.evaluate(frame: frame, visibleFrame: frame, bandFrame: band,
                             windows: windows, systemFullScreen: systemFullScreen, displayFrames: displayFrames)
  }

  func testAnAutoHiddenMenuBarStillAnimatesAtLaunchAndOnActivation() {
    let evidence = autoHiddenEvidence([desktop()])
    XCTAssertEqual(evidence.context, .fullScreen)
    XCTAssertFalse(evidence.menuVisible)
    XCTAssertTrue(CornerVisibility.visible(evidence))
    let sample = BandEntrance.Sample(evidence)
    XCTAssertEqual(step(sample, event: .settings), .start)
    XCTAssertNil(step(sample, event: .settings))
    XCTAssertEqual(step(sample, enabled: false, event: .settings), .restore)
    XCTAssertEqual(step(sample, event: .settings), .start)
  }

  func testAHiddenMenuBarStillAnimatesOnReturnFromShowDesktop() {
    let ordinary = autoHiddenEvidence([desktop()])
    let revealed = autoHiddenEvidence([desktop(), desktop(layer: 18)])
    XCTAssertFalse(CornerVisibility.visible(revealed))
    XCTAssertTrue(CornerVisibility.visible(ordinary))
    _ = step(BandEntrance.Sample(ordinary), event: .settings)
    XCTAssertEqual(step(BandEntrance.Sample(revealed)), .restore)
    XCTAssertEqual(step(BandEntrance.Sample(ordinary)), .start)
  }

  func testAnAutoHiddenMenuBarAnimatesWithFullScreenOnAnotherDisplay() {
    let otherDisplay = frame.offsetBy(dx: frame.width, dy: 0)
    let otherBackdrop = MenuBarEvidence.Window(
      owner: .desktop, layer: MenuBarEvidence.fullScreenBackdropLayer,
      bounds: otherDisplay, isWindowManager: true)
    let displays = [frame, otherDisplay]
    let windows = [desktop(), otherBackdrop]
    let ordinary = autoHiddenEvidence(windows, systemFullScreen: true, displayFrames: displays)
    let revealed = autoHiddenEvidence(windows + [desktop(layer: 18)], systemFullScreen: true, displayFrames: displays)

    XCTAssertEqual(step(BandEntrance.Sample(ordinary), event: .settings), .start)
    XCTAssertEqual(step(BandEntrance.Sample(revealed)), .restore)
    XCTAssertEqual(step(BandEntrance.Sample(ordinary)), .start)

    let withoutOtherDisplay = autoHiddenEvidence(windows, systemFullScreen: true, displayFrames: [frame])
    XCTAssertEqual(BandEntrance.Sample(withoutOtherDisplay), .unavailable)

    let bothInFullScreen = autoHiddenEvidence(windows + [desktop(layer: MenuBarEvidence.fullScreenBackdropLayer)],
                                             systemFullScreen: true, displayFrames: displays)
    XCTAssertEqual(BandEntrance.Sample(bothInFullScreen), .unavailable)
  }

  func testFullScreenWithoutAMenuBarInterruptsAndDoesNotReplayOnReturn() {
    let ordinary = BandEntrance.Sample(autoHiddenEvidence([desktop()]))
    let coveringApp = MenuBarEvidence.Window(owner: .application, layer: 0, bounds: frame)
    let shell = desktop(layer: MenuBarEvidence.fullScreenBackdropLayer)
    let samples = [
      autoHiddenEvidence([desktop(), coveringApp]),
      autoHiddenEvidence([desktop(), shell]),
      autoHiddenEvidence([desktop()], systemFullScreen: true)
    ]
    for evidence in samples {
      state = BandEntrance()
      _ = step(ordinary, event: .settings)
      XCTAssertEqual(BandEntrance.Sample(evidence), .unavailable)
      XCTAssertEqual(step(BandEntrance.Sample(evidence)), .restore)
      XCTAssertNil(step(ordinary))
    }
  }

  func testSlidingAndMissingEvidenceDisarmAReturnWithTheMenuHidden() {
    let ordinary = BandEntrance.Sample(autoHiddenEvidence([desktop()]))
    let revealed = BandEntrance.Sample(autoHiddenEvidence([desktop(), desktop(layer: 18)]))
    let sliding = autoHiddenEvidence([desktop(), desktop(offset: 200)])
    let malformed = MenuBarEvidence.windows(from: [[:]], ownPID: 42, primaryScreenHeight: frame.height)
    XCTAssertTrue(sliding.spaceSliding)
    XCTAssertNil(malformed)
    for evidence in [sliding, autoHiddenEvidence(malformed), autoHiddenEvidence([])] {
      state = BandEntrance()
      _ = step(ordinary, event: .settings)
      _ = step(revealed)
      XCTAssertEqual(BandEntrance.Sample(evidence), .unavailable)
      XCTAssertEqual(step(BandEntrance.Sample(evidence)), .restore)
      XCTAssertNil(step(ordinary))
    }
  }

  private let reservedVisible = CGRect(x: 0, y: 0, width: 1512, height: 949)
  private var menu: MenuBarEvidence.Window { .init(owner: .windowServer, layer: 24, bounds: band) }

  private func reservedEvidence(_ windows: [MenuBarEvidence.Window]?,
                                systemFullScreen: Bool = false) -> MenuBarEvidence.Result {
    MenuBarEvidence.evaluate(frame: frame, visibleFrame: reservedVisible, bandFrame: band,
                             windows: windows, systemFullScreen: systemFullScreen)
  }

  /// The usual layout: the menu bar is always visible and reserves the top of the display.
  func testAVisibleMenuBarAnimatesAtLaunchAndOnReturnFromShowDesktop() {
    let ordinary = reservedEvidence([desktop(), menu])
    let revealed = reservedEvidence([desktop(), menu, desktop(layer: 18)])
    XCTAssertEqual(ordinary.context, .desktop)
    XCTAssertTrue(ordinary.menuVisible)
    XCTAssertEqual(BandEntrance.Sample(ordinary), .desktop)
    XCTAssertEqual(BandEntrance.Sample(revealed), .revealed)
    XCTAssertEqual(step(BandEntrance.Sample(ordinary), event: .settings), .start)
    XCTAssertEqual(step(BandEntrance.Sample(revealed)), .restore)
    XCTAssertEqual(step(BandEntrance.Sample(ordinary)), .start)
    XCTAssertNil(step(BandEntrance.Sample(ordinary)))
  }

  func testAReservedTopWithoutTheMenuSurfacePermitsOnlyAnOrdinaryReveal() {
    XCTAssertEqual(BandEntrance.Sample(reservedEvidence([desktop()])), .unavailable)
    let revealed = [desktop(), desktop(layer: 18)]
    XCTAssertEqual(BandEntrance.Sample(reservedEvidence(revealed)), .revealed)
    XCTAssertEqual(BandEntrance.Sample(reservedEvidence(revealed, systemFullScreen: true)), .unavailable)
  }

  /// A full-screen Space that shows the menu bar keeps the menu surface, reserves the top and adds
  /// the backdrop (measured on 19 and 20 November). Its entrance was missing: a defect reported by
  /// the user. A covering app, a slide and missing evidence still interrupt without replay.
  func testWithAVisibleMenuBarFullScreenSlidingAndMissingEvidenceInterruptWithoutReplay() {
    let ordinary = BandEntrance.Sample(reservedEvidence([desktop(), menu]))
    let shownMenu = reservedEvidence([desktop(), menu, desktop(layer: MenuBarEvidence.fullScreenBackdropLayer)])
    XCTAssertEqual(BandEntrance.Sample(shownMenu), .desktop)
    let samples = [
      reservedEvidence([desktop(), menu, .init(owner: .application, layer: 0, bounds: frame)]),
      reservedEvidence([desktop(), menu, desktop(offset: 200)]),
      reservedEvidence([desktop(offset: 200)]),
      reservedEvidence(nil)
    ]
    for evidence in samples {
      state = BandEntrance()
      XCTAssertEqual(step(ordinary, event: .settings), .start)
      XCTAssertEqual(BandEntrance.Sample(evidence), .unavailable)
      XCTAssertEqual(step(BandEntrance.Sample(evidence)), .restore)
      XCTAssertNil(step(ordinary))
    }
  }

  func testOnlyASettingsEventActivates() {
    XCTAssertNil(step(.desktop))
    XCTAssertNil(step(.desktop, event: .settings))
    state = BandEntrance()
    XCTAssertEqual(step(.desktop, event: .system), .restore)
    XCTAssertNil(step(.desktop, event: .settings))
  }

  /// Any order of events, samples, displays and switches matches a model written per display.
  func testRandomTransitionsMatchThePerDisplayModel() {
    var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    func next(_ bound: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int((seed >> 33) % UInt64(bound))
    }
    let events: [BandEntrance.Event] = [.sample, .sample, .sample, .settings, .system]
    let kinds: [BandEntrance.Sample?] = [.desktop, .desktop, .revealed, .revealed, .unavailable, nil]
    var starts = 0
    for _ in 0..<300 {
      var entrance = BandEntrance()
      var model = EntranceModel()
      for _ in 0..<80 {
        let event = events[next(events.count)]
        let enabled = next(10) != 0
        let reduced = next(12) == 0
        var samples: [UInt32: BandEntrance.Sample] = [:]
        for id in [UInt32(1), 2, 12] {
          if let sample = kinds[next(kinds.count)] { samples[id] = sample }
        }
        let actions = entrance.update(event, enabled: enabled, samples: samples, reduceMotion: reduced)
        let expected = model.update(event, enabled: enabled, samples: samples, reduced: reduced)
        XCTAssertEqual(actions, expected)
        for (id, action) in actions where action == .start {
          starts += 1
          XCTAssertEqual(samples[id], .desktop)
          XCTAssertTrue(enabled && !reduced && event != .system)
        }
      }
    }
    XCTAssertGreaterThan(starts, 100)
  }

  func testRevealOnOneDisplayLeavesItsNeighbourAlone() {
    _ = state.update(.settings, enabled: true, samples: [1: .desktop, 2: .desktop], reduceMotion: false)
    let hide = state.update(.sample, enabled: true, samples: [1: .revealed, 2: .desktop], reduceMotion: false)
    XCTAssertEqual(hide, [1: .restore])
    let show = state.update(.sample, enabled: true, samples: [1: .desktop, 2: .desktop], reduceMotion: false)
    XCTAssertEqual(show, [1: .start])
  }
}

/// What each display showed last, kept apart from the type under test.
private struct EntranceModel {
  enum Display { case desktop, revealed, blocked }
  var displays: [UInt32: Display] = [:]
  var wasEnabled = false

  mutating func update(_ event: BandEntrance.Event, enabled: Bool, samples: [UInt32: BandEntrance.Sample],
                       reduced: Bool) -> [UInt32: BandEntrance.Action] {
    let activating = event == .settings && enabled && !wasEnabled
    wasEnabled = enabled
    var actions: [UInt32: BandEntrance.Action] = [:]
    var next: [UInt32: Display] = [:]
    for id in Set(displays.keys).union(samples.keys) {
      guard enabled, let sample = samples[id] else {
        if displays[id] != nil { actions[id] = .restore }
        continue
      }
      let before = displays[id]
      switch sample {
      case .desktop: next[id] = .desktop
      case .unavailable: next[id] = .blocked
      case .revealed: next[id] = event == .system || before == .blocked ? .blocked : .revealed
      }
      if event == .system || sample != .desktop || reduced {
        actions[id] = .restore
      } else if activating || before == .revealed {
        actions[id] = .start
      }
    }
    displays = next
    return actions
  }
}
