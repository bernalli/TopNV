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
      let screen = display(gap: 24, safeArea: 38, scale: scale, origin: CGPoint(x: -1512, y: 100))
      let band = BarGeometry.band(screen)
      let measured = menu(on: screen, depth: 33)
      let window = MenuBarEvidence.Window(owner: .windowServer, layer: Int(CGWindowLevelForKey(.mainMenuWindow)),
                                          bounds: measured)
      let evidence = MenuBarEvidence.evaluate(frame: screen.frame, visibleFrame: screen.visibleFrame,
                                              bandFrame: menu(on: screen, depth: 38), windows: [window])
      XCTAssertEqual(evidence.menuBounds, measured)
      let edge = BarGeometry.edge(menuBounds: evidence.menuBounds, band: band)
      XCTAssertEqual(BarGeometry.pixels(edge, on: screen),
                     PixelRect(x: 0, y: Int(33 * scale), width: Int(1512 * scale), height: Int(2 * scale)))
    }
  }

  func testEdgeCoversOnlyTheLastTwoPixelsOfTheRecordedBand() {
    let screen = display()
    let band = BarGeometry.band(screen)
    let edge = BarGeometry.edge(menuBounds: menu(on: screen, depth: 33), band: band)
    let pixels = BarGeometry.pixels(edge, on: screen)
    XCTAssertEqual(pixels, PixelRect(x: 0, y: 66, width: 3024, height: 2))
    XCTAssertEqual(BarGeometry.blackBottom(band: BarGeometry.pixels(band, on: screen), edge: pixels), 68)
  }

  func testNoEdgeWithoutAMeasuredMenu() {
    let screen = display()
    let evidence = MenuBarEvidence.evaluate(frame: screen.frame, visibleFrame: screen.visibleFrame,
                                            bandFrame: menu(on: screen, depth: 34), windows: [])
    XCTAssertNil(evidence.menuBounds)
    let edge = BarGeometry.edge(menuBounds: evidence.menuBounds, band: BarGeometry.band(screen))
    XCTAssertNil(edge)
    XCTAssertNil(BarGeometry.pixels(edge, on: screen))
  }

  func testNoEdgeFromNonFiniteGeometry() {
    let band = CGRect(x: 0, y: 948, width: 1512, height: 34)
    for value in [CGFloat.nan, .infinity, -.infinity] {
      XCTAssertNil(BarGeometry.edge(menuBounds: CGRect(x: 0, y: value, width: 1512, height: 33), band: band))
      XCTAssertNil(BarGeometry.edge(menuBounds: CGRect(x: 0, y: 949, width: 1512, height: 33),
                                    band: CGRect(x: 0, y: value, width: 1512, height: 34)))
    }
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
    for depth: CGFloat? in [nil, gap, midway, band?.height, band.map { $0.height + 3 }] {
      let measured = depth.map { menu(on: screen, depth: $0) }
      let edge = BarGeometry.edge(menuBounds: measured, band: band)
      let context = "scale=\(screen.scale) gap=\(gap) safeArea=\(screen.safeAreaTop) " +
        "origin=\(screen.frame.origin) depth=\(String(describing: depth))"
      if let depth, let band, depth < band.height {
        let frame = try XCTUnwrap(edge, context)
        XCTAssertGreaterThanOrEqual(frame.minY, band.minY, context)
        for corner in [ScreenCorner.topLeft, .topRight] {
          XCTAssertGreaterThanOrEqual(frame.minY, try XCTUnwrap(corners[corner], context).maxY, context)
        }
      } else {
        XCTAssertNil(edge, context)
      }
      for rect in Array(corners.values) + [band, edge].compactMap({ $0 }) {
        let pixels = try XCTUnwrap(BarGeometry.pixels(rect, on: screen), context)
        XCTAssertGreaterThanOrEqual(pixels.x, 0, context)
        XCTAssertGreaterThanOrEqual(pixels.y, 0, context)
        XCTAssertLessThanOrEqual(pixels.x + pixels.width, Int(screen.frame.width * screen.scale), context)
        XCTAssertLessThanOrEqual(pixels.bottom, Int(screen.frame.height * screen.scale), context)
      }

      let bandPixels = BarGeometry.pixels(band, on: screen)
      let edgePixels = BarGeometry.pixels(edge, on: screen)
      let strips = [bandPixels, edgePixels].compactMap { $0 }
      let rows = Set(strips.flatMap { Array($0.y..<$0.bottom) })
      let bottom = BarGeometry.blackBottom(band: bandPixels, edge: edgePixels)
      XCTAssertEqual(bottom, bandPixels?.bottom ?? 0, context)
      XCTAssertEqual(rows, Set(0..<bottom), context)
    }
  }

  func testAMenuDeeperThanTheBandLeavesRowsToTheMenuSurface() throws {
    let screen = display()
    let measured = menu(on: screen, depth: 37)
    let band = BarGeometry.band(screen)
    let edge = BarGeometry.edge(menuBounds: measured, band: band)
    XCTAssertNil(edge)
    let bandPixels = BarGeometry.pixels(band, on: screen)
    let menuPixels = try XCTUnwrap(BarGeometry.pixels(measured, on: screen))
    let bottom = BarGeometry.blackBottom(band: bandPixels, edge: BarGeometry.pixels(edge, on: screen))
    XCTAssertEqual(bottom, 68)
    XCTAssertEqual(menuPixels.bottom, 74)
  }
}
