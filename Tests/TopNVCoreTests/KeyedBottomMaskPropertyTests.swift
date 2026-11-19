import CoreGraphics
import XCTest
@testable import TopNVCore

final class KeyedBottomMaskPropertyTests: XCTestCase {
  /// For every bar height and scale the plate starts on a pixel row, never above 7.5 points
  /// from the bottom of the menu bar, less than one pixel below it, and reaches the window bottom.
  func testThePlateIsPixelAlignedAndNeverCoversTheGlyphRows() {
    for scale in [CGFloat(1), 2, 3] {
      for menu in stride(from: CGFloat(22), through: 44, by: 0.5) {
        for extra in [CGFloat(0), 1, 5] {
          for flipped in [false, true] {
            let size = CGSize(width: 1512, height: menu + extra)
            let mask = ScreenGeometry.keyedBottomMask(size: size, menuHeight: menu, scale: scale, flipped: flipped)
            let top = flipped ? mask.minY : size.height - mask.maxY
            let label = "scale \(scale) menu \(menu) extra \(extra) flipped \(flipped)"
            XCTAssertEqual((top * scale).rounded(), top * scale, accuracy: 1e-9, label)
            XCTAssertGreaterThanOrEqual(top, menu - 7.5 - 1e-9, label)
            XCTAssertLessThan(top, menu - 7.5 + 1 / scale, label)
            XCTAssertEqual(flipped ? mask.maxY : size.height - mask.minY, size.height, accuracy: 1e-9, label)
            XCTAssertEqual(mask.minX, 0, label)
            XCTAssertEqual(mask.width, size.width, label)
          }
        }
      }
    }
  }

  func testAMenuTallerThanTheWindowIsMeasuredFromTheWindowBottom() {
    let size = CGSize(width: 1512, height: 33)
    for flipped in [false, true] {
      XCTAssertEqual(ScreenGeometry.keyedBottomMask(size: size, menuHeight: 40, scale: 2, flipped: flipped),
                     ScreenGeometry.keyedBottomMask(size: size, menuHeight: 33, scale: 2, flipped: flipped))
    }
  }

  func testDegenerateGeometryStaysInsideTheWindow() {
    let sizes = [CGSize(width: 1512, height: 33), CGSize(width: 1512, height: 4), CGSize(width: 0, height: 0)]
    let menus: [CGFloat] = [-5, 0, 3, 33, 500, .nan, .infinity]
    let scales: [CGFloat] = [0, -2, 1, 2, .nan, .infinity]
    for size in sizes {
      for menu in menus {
        for scale in scales {
          for flipped in [false, true] {
            let mask = ScreenGeometry.keyedBottomMask(size: size, menuHeight: menu, scale: scale, flipped: flipped)
            let label = "size \(size) menu \(menu) scale \(scale)"
            XCTAssertTrue([mask.minX, mask.minY, mask.width, mask.height].allSatisfy(\.isFinite), label)
            XCTAssertGreaterThanOrEqual(mask.minY, 0, label)
            XCTAssertGreaterThanOrEqual(mask.height, 0, label)
            XCTAssertLessThanOrEqual(mask.maxY, size.height + 1e-9, label)
          }
        }
      }
    }
  }
}
