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

  func testRevealOnOneDisplayLeavesItsNeighbourAlone() {
    _ = state.update(.settings, enabled: true, samples: [1: .desktop, 2: .desktop], reduceMotion: false)
    let hide = state.update(.sample, enabled: true, samples: [1: .revealed, 2: .desktop], reduceMotion: false)
    XCTAssertEqual(hide, [1: .restore])
    let show = state.update(.sample, enabled: true, samples: [1: .desktop, 2: .desktop], reduceMotion: false)
    XCTAssertEqual(show, [1: .start])
  }
}
