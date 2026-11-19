import CoreGraphics
import XCTest
@testable import TopNVCore

final class KeyedBottomMaskTests: XCTestCase {
  func testRetinaMenuCoversRow51AndLeavesTheLastGlyphRow50Free() {
    // The 3024 x 66 strip has a gradient at rows 51...53. Text reaches row 50.
    for height in [CGFloat(33), 34, 36] {
      for flipped in [false, true] {
        let size = CGSize(width: 1512, height: height)
        let mask = ScreenGeometry.keyedBottomMask(size: size, menuHeight: 33, scale: 2, flipped: flipped)
        let firstPixel = (flipped ? mask.minY : height - mask.maxY) * 2
        XCTAssertEqual(firstPixel, 51)
        XCTAssertEqual(flipped ? mask.maxY : height - mask.minY, height)
        XCTAssertEqual(mask.width * 2, 3024)
      }
    }
  }

  func testHiddenMenuUsesTheBandAndOneTimesScalePreservesWholeGlyphPixels() {
    let size = CGSize(width: 1512, height: 33)
    let retina = ScreenGeometry.keyedBottomMask(size: size, menuHeight: 0, scale: 2, flipped: true)
    XCTAssertEqual(retina, CGRect(x: 0, y: 25.5, width: 1512, height: 7.5))
    let standard = ScreenGeometry.keyedBottomMask(size: size, menuHeight: 0, scale: 1, flipped: true)
    XCTAssertEqual(standard, CGRect(x: 0, y: 26, width: 1512, height: 7))
  }
}
