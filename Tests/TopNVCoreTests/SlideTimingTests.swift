import XCTest
@testable import TopNVCore

final class SlideTimingTests: XCTestCase {
  /// Each range is a slide sampled at 10 Hz. At rest the menu is visible again.
  private func assertGateStaysOn(slides: [Range<Int>], file: StaticString = #filePath, line: UInt = #line) {
    var state = KeyedOverlayState()
    for tick in -1..<(slides.last?.upperBound ?? 0) {
      let sliding = slides.contains { $0.contains(tick) }
      _ = state.update(.init(activeWindowIDs: [1], appearance: .light, context: .desktop,
                             menuVisible: !sliding, enabled: true, now: 10 + Double(tick) / 10,
                             spaceSliding: sliding))
      guard state.visibility[1] == true else {
        return XCTFail("Gate lost at tick \(tick)", file: file, line: line)
      }
    }
  }

  func testConsecutiveSlidesWithShortRestsKeepTheGate() {
    // 10:59:39.534: 1.6 s moving, 0.3 s at rest, 2.6 s moving. Repeat the
    // pair so raising the cap alone cannot conceal a timer shared by gestures.
    assertGateStaysOn(slides: [0..<16, 19..<45, 48..<64, 67..<93])
  }

  func testHeldSlideKeepsTheGateUntilRelease() {
    // 11:00:05.834 to 11:00:10.231, including the gate loss at 11:00:09.430.
    assertGateStaysOn(slides: [0..<44])
  }

  private func sample(_ state: inout KeyedOverlayState, now: Double, sliding: Bool, menu: Bool)
    -> KeyedOverlayState.Decision {
    state.update(.init(activeWindowIDs: [1], appearance: .light, context: .desktop,
                       menuVisible: menu, enabled: true, now: now, spaceSliding: sliding))
  }

  /// A stuck signal that drops one or two samples in a row is still one slide, whatever the
  /// length of its runs: only a real rest starts a new measure.
  func testAStuckSignalWithShortDropoutsIsBoundedForEveryRunLength() throws {
    for run in 1...8 {
      for dropout in 1...2 {
        var state = KeyedOverlayState()
        _ = sample(&state, now: 10, sliding: false, menu: true)
        var hiddenAt: Double?
        for step in 0..<100 {
          let time = 20 + 0.1 * Double(step)
          let result = sample(&state, now: time, sliding: step % (run + dropout) < run, menu: false)
          if result.gates[1] == false, hiddenAt == nil { hiddenAt = time }
        }
        XCTAssertLessThanOrEqual(try XCTUnwrap(hiddenAt, "run \(run) dropout \(dropout)"), 25.51,
                                 "run \(run) dropout \(dropout)")
      }
    }
  }

  /// A sliding sample whose clock is not finite must neither leave the next slide without
  /// protection nor remove its cap.
  func testANonFiniteClockWhileSlidingLeavesTheNextSlideProtectedAndBounded() throws {
    for bad in [Double.nan, .infinity, -.infinity] {
      var state = KeyedOverlayState()
      _ = sample(&state, now: 10, sliding: false, menu: true)
      _ = sample(&state, now: bad, sliding: true, menu: true)
      _ = sample(&state, now: 20, sliding: false, menu: true)
      var hiddenAt: Double?
      for step in 1..<100 {
        let time = 20 + 0.1 * Double(step)
        if sample(&state, now: time, sliding: true, menu: false).gates[1] == false, hiddenAt == nil {
          hiddenAt = time
        }
      }
      XCTAssertEqual(try XCTUnwrap(hiddenAt, "\(bad)"), 25.6, accuracy: 0.11, "\(bad)")
    }
  }
}
