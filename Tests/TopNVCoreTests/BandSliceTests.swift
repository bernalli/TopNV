import XCTest
@testable import TopNVCore

final class BandSliceTests: XCTestCase {
  func testSlicesCoverOddAndEvenWidthsAndTrackTheCalmFront() {
    for width: CGFloat in [1512, 1501, 32] {
      let frame = CGRect(x: -300, y: 716, width: width, height: 33)
      let slices = BandSlice.pairs(in: frame)
      XCTAssertEqual(slices.first?.right.minX, frame.midX)
      XCTAssertEqual(slices.last?.left.minX, frame.minX)
      XCTAssertEqual(slices.last?.right.maxX, frame.maxX)
      for (inner, outer) in zip(slices, slices.dropFirst()) {
        XCTAssertEqual(inner.left.minX, outer.left.maxX)
        XCTAssertEqual(inner.right.maxX, outer.right.minX)
      }
      for slice in slices {
        XCTAssertEqual(slice.left.size, slice.right.size)
        XCTAssertEqual(slice.right.height, frame.height)
        XCTAssertEqual(slice.opacity(radius: 0), 0)
        var last = 0.0
        for tick in 0...36 {
          let elapsed = Double(tick) / 36 * BarAnimation.calm.durationMS
          let front = BarAnimation.calm.frame(at: elapsed, width: width, height: 33, notch: 140)
          let alpha = slice.opacity(radius: front.halfWidth)
          XCTAssertGreaterThanOrEqual(alpha, last)
          last = alpha
        }
        XCTAssertEqual(last, 1)
      }
    }
  }
}
