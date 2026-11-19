import CoreGraphics
import XCTest
import TopNVCore

final class BarPixelsTests: XCTestCase {
  private let display = CGRect(x: -1512, y: 100, width: 1512, height: 982)

  func testPixelsUseTheTopLeftOriginOfTheDisplay() {
    let band = CGRect(x: -1512, y: 1048, width: 1512, height: 34)
    let pixels = BarPixels.pixels(band, display: display, scale: 2)
    XCTAssertEqual(pixels?.description, "0,0,3024,68")
    XCTAssertEqual(pixels?.bottom, 68)
  }

  func testPixelsRoundOutwardAndContainTheExactRect() throws {
    for scale: CGFloat in [1, 2, 3] {
      for horizontal in -8...8 {
        for vertical in -8...8 {
          let rect = CGRect(x: display.minX + CGFloat(horizontal) / 4, y: display.maxY + CGFloat(vertical) / 4 - 5,
                            width: 7, height: 5)
          let pixels = try XCTUnwrap(BarPixels.pixels(rect, display: display, scale: scale))
          let left = (rect.minX - display.minX) * scale
          let top = (display.maxY - rect.maxY) * scale
          let right = left + rect.width * scale
          let bottom = top + rect.height * scale
          XCTAssertEqual(CGFloat(pixels.x), left.rounded(.down))
          XCTAssertEqual(CGFloat(pixels.y), top.rounded(.down))
          XCTAssertEqual(CGFloat(pixels.x + pixels.width), right.rounded(.up))
          XCTAssertEqual(CGFloat(pixels.bottom), bottom.rounded(.up))
        }
      }
    }
  }

  func testLayerRectInAKeyWindowMapsToDisplayPixelsForBothFlips() {
    let window = CGRect(x: -1512, y: 1048, width: 1512, height: 34)
    for flipped in [false, true] {
      let layer = CGRect(x: 0, y: flipped ? 25.5 : 0, width: 1512, height: 8.5)
      let rect = BarPixels.windowRect(layerFrame: layer, window: window, flipped: flipped)
      XCTAssertEqual(BarPixels.pixels(rect, display: display, scale: 2)?.description, "0,51,3024,17")
    }
  }

  func testInvalidInputGivesNoPixels() {
    let invalid = [CGRect.null, .infinite, CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1),
                   CGRect(x: 0, y: 0, width: 1, height: CGFloat.infinity),
                   CGRect(x: 0, y: 0, width: 0, height: 1), CGRect(x: 0, y: 0, width: 1, height: -1)]
    for rect in invalid {
      XCTAssertNil(BarPixels.pixels(rect, display: display, scale: 2))
      XCTAssertNil(BarPixels.pixels(display, display: rect, scale: 2))
    }
    for scale: CGFloat in [0, -1, .nan, .infinity] {
      XCTAssertNil(BarPixels.pixels(display, display: display, scale: scale))
    }
  }
}
