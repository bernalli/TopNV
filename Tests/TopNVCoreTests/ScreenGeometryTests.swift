import CoreGraphics
import XCTest

@testable import TopNVCore

final class ScreenGeometryTests: XCTestCase {
  // A 14-inch MacBook Pro in its default scaled mode, with the Dock at the bottom.
  private let notchedFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let notchedVisible = CGRect(x: 0, y: 70, width: 1512, height: 879)  // maxY = 949

  // MARK: - Notch detection

  func testNotchDetection() {
    XCTAssertTrue(ScreenGeometry.isNotched(safeAreaTop: 32))
    XCTAssertFalse(ScreenGeometry.isNotched(safeAreaTop: 0))
  }

  // MARK: - Bar rect

  func testBarRectOnNotchedScreenUsesMenuBarGap() {
    let rect = ScreenGeometry.barRect(
      frame: notchedFrame, visibleFrame: notchedVisible, safeAreaTop: 32)
    XCTAssertEqual(rect, CGRect(x: 0, y: 949, width: 1512, height: 33))
  }

  func testBarRectIsNilOnScreenWithoutNotch() {
    let frame = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    let visible = CGRect(x: 0, y: 0, width: 2560, height: 1415)
    XCTAssertNil(ScreenGeometry.barRect(frame: frame, visibleFrame: visible, safeAreaTop: 0))
    XCTAssertEqual(
      ScreenGeometry.menuBarHeight(frame: frame, visibleFrame: visible, safeAreaTop: 0), 25)
  }

  func testBarRectWithAutoHiddenMenuBarFallsBackToSafeAreaInset() {
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 982)  // maxY == frame.maxY
    let rect = ScreenGeometry.barRect(frame: notchedFrame, visibleFrame: visible, safeAreaTop: 32)
    XCTAssertEqual(rect, CGRect(x: 0, y: 950, width: 1512, height: 32))
  }

  func testBarRectOnScreenWithNonZeroOrigin() {
    let frame = CGRect(x: -1728, y: 200, width: 1728, height: 1117)  // maxY = 1317
    let visible = CGRect(x: -1728, y: 200, width: 1728, height: 1079)  // maxY = 1279
    let rect = ScreenGeometry.barRect(frame: frame, visibleFrame: visible, safeAreaTop: 32)
    XCTAssertEqual(rect, CGRect(x: -1728, y: 1279, width: 1728, height: 38))
  }

  // MARK: - Corner rects

  func testCornerRectsRadiusZeroProducesNoWindows() {
    XCTAssertTrue(ScreenGeometry.cornerRects(frame: notchedFrame, radius: 0).isEmpty)
    XCTAssertTrue(ScreenGeometry.cornerRects(frame: notchedFrame, radius: -5).isEmpty)
    XCTAssertTrue(ScreenGeometry.cornerRects(frame: notchedFrame, radius: .nan).isEmpty)
  }

  func testCornerRectsRadiusTen() {
    let rects = ScreenGeometry.cornerRects(frame: notchedFrame, radius: 10)
    XCTAssertEqual(rects.count, 4)
    XCTAssertEqual(rects[.topLeft], CGRect(x: 0, y: 972, width: 10, height: 10))
    XCTAssertEqual(rects[.topRight], CGRect(x: 1502, y: 972, width: 10, height: 10))
    XCTAssertEqual(rects[.bottomLeft], CGRect(x: 0, y: 0, width: 10, height: 10))
    XCTAssertEqual(rects[.bottomRight], CGRect(x: 1502, y: 0, width: 10, height: 10))
  }

  func testCornerRectsOnScreenWithNonZeroOrigin() {
    let frame = CGRect(x: 1512, y: -98, width: 1920, height: 1080)  // maxX 3432, maxY 982
    let rects = ScreenGeometry.cornerRects(frame: frame, radius: 10)
    XCTAssertEqual(rects[.topLeft], CGRect(x: 1512, y: 972, width: 10, height: 10))
    XCTAssertEqual(rects[.topRight], CGRect(x: 3422, y: 972, width: 10, height: 10))
    XCTAssertEqual(rects[.bottomLeft], CGRect(x: 1512, y: -98, width: 10, height: 10))
    XCTAssertEqual(rects[.bottomRight], CGRect(x: 3422, y: -98, width: 10, height: 10))
  }

  func testRadiusIsClampedToHalfTheShorterSide() {
    let frame = CGRect(x: 0, y: 0, width: 100, height: 40)
    XCTAssertEqual(ScreenGeometry.effectiveRadius(30, frame: frame), 20)
    XCTAssertEqual(ScreenGeometry.cornerRects(frame: frame, radius: 30)[.topRight]?.width, 20)
  }

  // MARK: - Arc centre

  func testArcCenterPointsTowardsScreenCentre() {
    XCTAssertEqual(ScreenGeometry.arcCenter(for: .topLeft, side: 10), CGPoint(x: 10, y: 0))
    XCTAssertEqual(ScreenGeometry.arcCenter(for: .topRight, side: 10), CGPoint(x: 0, y: 0))
    XCTAssertEqual(ScreenGeometry.arcCenter(for: .bottomLeft, side: 10), CGPoint(x: 10, y: 10))
    XCTAssertEqual(ScreenGeometry.arcCenter(for: .bottomRight, side: 10), CGPoint(x: 0, y: 10))
  }
}
