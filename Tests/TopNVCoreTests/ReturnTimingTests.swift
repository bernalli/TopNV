import XCTest
@testable import TopNVCore

final class ReturnTimingTests: XCTestCase {
  func testDeliveryDelayDoesNotAdvanceTheTrackAtReceipt() {
    for signal in [0.0, 80, 260, 292] {
      for delay in [0.0, 10, 35, 70] {
        let receipt = signal + delay
        var timing = ReturnTiming()
        let before = timing.progress(at: receipt)
        timing.surfaceEnded(at: signal, receivedAt: receipt)
        XCTAssertEqual(timing.progress(at: receipt), before, accuracy: 0.000_001)
        XCTAssertGreaterThanOrEqual(timing.progress(at: receipt + 1), before)
        XCTAssertEqual(timing.progress(at: max(ReturnTiming.durationMS, receipt + 100)), 1)
      }
    }
  }

  func testEarlyEndPreservesEveryVisibleFrameOfTheCalmEntrance() {
    let normal = ReturnTiming()
    for end in [0.0, 1, 25, 80, 180, 260] {
      var timing = ReturnTiming()
      timing.surfaceEnded(at: end)
      for elapsed in stride(from: 0.0, through: 270, by: 5) {
        XCTAssertEqual(timing.progress(at: elapsed), normal.progress(at: elapsed), accuracy: 0.000_001)
      }
      XCTAssertEqual(timing.progress(at: ReturnTiming.durationMS), 1)
    }
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
