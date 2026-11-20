import XCTest
@testable import TopNVCore

final class ReturnTimingTests: XCTestCase {
  func testEarlySurfaceEndShortensTheRemainingTrackWithoutJumping() {
    var timing = ReturnTiming()
    let before = timing.progress(at: 180)
    timing.surfaceEnded(at: 180)
    XCTAssertEqual(timing.progress(at: 180), before)
    XCTAssertGreaterThan(timing.progress(at: 195), before)
    XCTAssertLessThan(timing.progress(at: 195), 1)
    timing.surfaceEnded(at: 195)
    XCTAssertEqual(timing.progress(at: 247), 1)
  }

  func testLateSignalKeepsTheLastFramesUntilTheSurfaceLeaves() {
    var timing = ReturnTiming()
    XCTAssertEqual(timing.progress(at: 146), 0.5, accuracy: 0.001)
    XCTAssertLessThan(timing.progress(at: 320), 1)
    timing.surfaceEnded(at: 320)
    XCTAssertLessThan(timing.progress(at: 321), 1)
    XCTAssertEqual(timing.progress(at: 354), 1)
  }

  func testMissingSignalStillCompletesWithAContinuousTail() {
    let timing = ReturnTiming()
    let waiting = timing.progress(at: 325)
    XCTAssertEqual(timing.progress(at: 325.34), waiting, accuracy: 0.005)
    XCTAssertGreaterThan(timing.progress(at: 330), waiting)
    XCTAssertLessThan(timing.progress(at: 330), 1)
    XCTAssertEqual(timing.progress(at: 343), 1)
    XCTAssertEqual(timing.progress(at: 800), 1)
  }

  func testTypicalSignalFinishesWithinOneFrame() {
    var timing = ReturnTiming()
    timing.surfaceEnded(at: 292)
    XCTAssertGreaterThan(timing.progress(at: 292), 0.94)
    XCTAssertLessThan(timing.progress(at: 292), 1)
    XCTAssertEqual(timing.progress(at: 309), 1)
  }

  func testLateSignalDoesNotRestartTheTimeoutTail() {
    var timing = ReturnTiming()
    let before = timing.progress(at: 335)
    timing.surfaceEnded(at: 335)
    XCTAssertEqual(timing.progress(at: 335), before)
    XCTAssertEqual(timing.progress(at: 343), 1)
  }
}
