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
}
