import CoreGraphics
import XCTest
import TopNVCore

final class BarGeometryTests: XCTestCase {
  private func display(
    gap: CGFloat = 33, safeArea: CGFloat = 32, scale: CGFloat = 2, origin: CGPoint = .zero
  ) -> BarDisplay {
    let frame = CGRect(origin: origin, size: CGSize(width: 1512, height: 982))
    let visible = CGRect(origin: origin, size: CGSize(width: frame.width, height: frame.height - gap))
    return BarDisplay(id: 1, frame: frame, visibleFrame: visible, safeAreaTop: safeArea,
                      scale: scale, notchWidth: safeArea > 0 ? 200 : 0, isBuiltin: true)
  }

  private func menu(on display: BarDisplay, depth: CGFloat) -> CGRect {
    CGRect(x: display.frame.minX, y: display.frame.maxY - depth, width: display.frame.width, height: depth)
  }

  func testBandIsTheMenuGapPlusTheSeparator() {
    let screen = display()
    let band = BarGeometry.band(screen)
    XCTAssertEqual(BarGeometry.separator, 1)
    XCTAssertEqual(band, CGRect(x: 0, y: 948, width: 1512, height: 34))
    XCTAssertEqual(BarGeometry.pixels(band, on: screen), PixelRect(x: 0, y: 0, width: 3024, height: 68))
  }

  func testBandFallsBackToTheSafeAreaWithAnAutoHiddenMenu() {
    XCTAssertEqual(BarGeometry.band(display(gap: 0)), CGRect(x: 0, y: 950, width: 1512, height: 32))
  }

  func testNoBandWithoutANotch() {
    XCTAssertNil(BarGeometry.band(display(safeArea: 0)))
  }

  func testEdgeStartsAtTheMeasuredMenuBottomAndIsEdgeDepthDeep() {
    XCTAssertEqual(BarGeometry.edgeDepth, 2)
    for scale: CGFloat in [1, 2, 3] {
      let screen = display(gap: 24, scale: scale, origin: CGPoint(x: -1512, y: 100))
      let measured = menu(on: screen, depth: 33)
      let window = MenuBarEvidence.Window(owner: .windowServer, layer: Int(CGWindowLevelForKey(.mainMenuWindow)),
                                          bounds: measured)
      let evidence = MenuBarEvidence.evaluate(frame: screen.frame, visibleFrame: screen.visibleFrame,
                                              bandFrame: menu(on: screen, depth: 32), windows: [window])
      XCTAssertEqual(evidence.menuBounds, measured)
      let edge = BarGeometry.edge(menuBounds: evidence.menuBounds)
      XCTAssertEqual(BarGeometry.pixels(edge, on: screen),
                     PixelRect(x: 0, y: Int(33 * scale), width: Int(1512 * scale), height: Int(2 * scale)))
    }
  }

  func testNoEdgeWithoutAMeasuredMenu() {
    let screen = display()
    let evidence = MenuBarEvidence.evaluate(frame: screen.frame, visibleFrame: screen.visibleFrame,
                                            bandFrame: menu(on: screen, depth: 34), windows: [])
    XCTAssertNil(evidence.menuBounds)
    let edge = BarGeometry.edge(menuBounds: evidence.menuBounds)
    XCTAssertNil(edge)
    XCTAssertNil(BarGeometry.pixels(edge, on: screen))
  }

  func testPlateKeepsTheGlyphRowsFree() {
    let screen = display()
    let key = menu(on: screen, depth: 34)
    XCTAssertEqual(BarGeometry.plateGlyphMargin, 7.5)
    let plate = BarGeometry.plate(keySize: key.size, menuHeight: 33, scale: screen.scale)
    for (rect, flipped) in [(plate.flipped, true), (plate.unflipped, false)] {
      let frame = BarPixels.windowRect(layerFrame: rect, window: key, flipped: flipped)
      XCTAssertEqual(BarGeometry.pixels(frame, on: screen), PixelRect(x: 0, y: 51, width: 3024, height: 17))
    }
  }

  func testTopCornersStartAtTheBandBottomOrAtTheScreenTop() {
    let frame = display(origin: CGPoint(x: -1512, y: 100)).frame
    for height: CGFloat? in [34, nil] {
      let corners = BarGeometry.corners(display: frame, bandHeight: height, rounded: true)
      let top = frame.maxY - (height ?? 0)
      XCTAssertEqual(corners.count, 4)
      XCTAssertEqual(corners[.topLeft], CGRect(x: frame.minX, y: top - 15, width: 15, height: 15))
      XCTAssertEqual(corners[.topRight], CGRect(x: frame.maxX - 15, y: top - 15, width: 15, height: 15))
    }
  }

  func testNoCornersWhenRoundingIsOff() {
    XCTAssertTrue(BarGeometry.corners(display: display().frame, bandHeight: 34, rounded: false).isEmpty)
  }

  func testBlackBottomIsTheLowerOfBandAndEdge() {
    let band = PixelRect(x: 0, y: 0, width: 3024, height: 68)
    for top in [50, 66] {
      let edge = PixelRect(x: 0, y: top, width: 3024, height: 4)
      XCTAssertEqual(BarGeometry.blackBottom(band: band, edge: edge), max(68, top + 4))
      XCTAssertEqual(BarGeometry.blackBottom(band: nil, edge: edge), top + 4)
    }
    XCTAssertEqual(BarGeometry.blackBottom(band: band, edge: nil), 68)
    XCTAssertEqual(BarGeometry.blackBottom(band: nil, edge: nil), 0)
  }

  func testBandEdgeAndTopCornersLeaveNoRowUncoveredAboveBlackBottom() throws {
    for scale: CGFloat in [1, 2, 3] {
      for gap: CGFloat in [0, 24, 33, 37.5] {
        for safeArea: CGFloat in [0, 32, 38] {
          for origin in [CGPoint.zero, CGPoint(x: -1512, y: 100)] {
            let screen = display(gap: gap, safeArea: safeArea, scale: scale, origin: origin)
            try checkCoverage(on: screen, gap: gap)
          }
        }
      }
    }
  }

  private func checkCoverage(on screen: BarDisplay, gap: CGFloat) throws {
    let band = BarGeometry.band(screen)
    let corners = BarGeometry.corners(display: screen.frame, bandHeight: band?.height, rounded: true)
    XCTAssertEqual(corners.count, 4)
    let midway = (gap + (band?.height ?? gap)) / 2
    for depth: CGFloat? in [nil, gap, midway] {
      let measured = depth.map { menu(on: screen, depth: $0) }
      let edge = BarGeometry.edge(menuBounds: measured)
      let context = "scale=\(screen.scale) gap=\(gap) safeArea=\(screen.safeAreaTop) " +
        "origin=\(screen.frame.origin) depth=\(String(describing: depth))"
      XCTAssertEqual(edge != nil, measured != nil, context)
      for rect in Array(corners.values) + [band, edge].compactMap({ $0 }) {
        let pixels = try XCTUnwrap(BarGeometry.pixels(rect, on: screen), context)
        XCTAssertGreaterThanOrEqual(pixels.x, 0, context)
        XCTAssertGreaterThanOrEqual(pixels.y, 0, context)
        XCTAssertLessThanOrEqual(pixels.x + pixels.width, Int(screen.frame.width * screen.scale), context)
        XCTAssertLessThanOrEqual(pixels.bottom, Int(screen.frame.height * screen.scale), context)
      }

      // On a display without a notch both the band and its edge are closed.
      let bandPixels = BarGeometry.pixels(band, on: screen)
      let edgePixels = screen.safeAreaTop > 0 ? BarGeometry.pixels(edge, on: screen) : nil
      let strips = [bandPixels, edgePixels].compactMap { $0 }
      let rows = Set(strips.flatMap { Array($0.y..<$0.bottom) })
      let bottom = BarGeometry.blackBottom(band: bandPixels, edge: edgePixels)
      XCTAssertEqual(rows, Set(0..<bottom), context)
    }
  }

  func testAMenuDeeperThanTheBandLeavesRowsToTheMenuSurface() throws {
    let screen = display()
    let measured = menu(on: screen, depth: 37)
    let band = try XCTUnwrap(BarGeometry.pixels(BarGeometry.band(screen), on: screen))
    let edge = try XCTUnwrap(BarGeometry.pixels(BarGeometry.edge(menuBounds: measured), on: screen))
    let menuPixels = try XCTUnwrap(BarGeometry.pixels(measured, on: screen))
    let bottom = BarGeometry.blackBottom(band: band, edge: edge)
    let uncovered = Set(0..<bottom).subtracting(band.y..<band.bottom).subtracting(edge.y..<edge.bottom)
    XCTAssertEqual(uncovered, Set(68..<74))
    XCTAssertTrue(uncovered.isSubset(of: Set(menuPixels.y..<menuPixels.bottom)))
  }
}
