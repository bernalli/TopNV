import CoreGraphics
import XCTest
@testable import TopNVCore

final class BarEntranceMaskTests: XCTestCase {
  private let size = CGSize(width: 1000, height: 34)

  func testCalmBandMaskGrowsFromTheNotchToBothEdges() {
    var previous: CGFloat = 0
    for time in [0.0, 100, 180, 300, 410.4, 570] {
      guard case .rect(let rect) = BarEntranceMask.band(elapsedMS: time, bandSize: size, notchWidth: 180) else {
        return XCTFail("Missing band mask")
      }
      XCTAssertEqual(rect.midX, 500, accuracy: 0.001)
      XCTAssertEqual(rect.minY, 0)
      XCTAssertEqual(rect.height, 34)
      if time == 0 { XCTAssertEqual(rect.width, 158) }
      if time < 570 { XCTAssertGreaterThan(rect.width, previous) }
      if time >= 410.4 { XCTAssertEqual(rect.width, 1000) }
      previous = rect.width
    }
  }

  func testAHiddenEntranceGivesAnEmptyMask() {
    let frame = CGRect(origin: .zero, size: size)
    for time in [-600.0, -1, -0.001] {
      let mask = BarEntranceMask.band(elapsedMS: time, bandSize: size, notchWidth: 150)
      XCTAssertEqual(mask, .rect(.zero))
      XCTAssertEqual(BarEntranceMask.edge(band: mask, bandFrame: frame, edgeFrame: frame), .rect(.zero))
      XCTAssertEqual(BarEntranceMask.keyBackdropExtent(band: mask, bandSize: size), .zero)
    }
    XCTAssertEqual(BarEntranceMask.edge(band: .none, bandFrame: frame, edgeFrame: frame), .none)
  }

  func testTheEdgeMaskGrowsFromItsTopEdge() throws {
    let frame = CGRect(x: 100, y: 100, width: 200, height: 34)
    struct GrowthCase {
      let edgeOrigin: CGFloat
      let initialHeight: CGFloat
      let partialHeight: CGFloat
    }
    let growthCases: [GrowthCase] = [
      .init(edgeOrigin: 99, initialHeight: 32.5, partialHeight: 33.5),
      .init(edgeOrigin: 98, initialHeight: 31.5, partialHeight: 33),
      .init(edgeOrigin: 97, initialHeight: 31.5, partialHeight: 33)
    ]
    for growth in growthCases {
      let edge = CGRect(x: 100, y: growth.edgeOrigin, width: 200, height: 2)
      func path(_ height: CGFloat) throws -> CGPath {
        let source = BarMask.rect(CGRect(x: 0, y: 0, width: 200, height: height))
        let mask = BarEntranceMask.edge(band: source, bandFrame: frame, edgeFrame: edge)
        return try XCTUnwrap(BarEntranceMask.path(mask, height: 2, flipped: true))
      }
      let nearTop = CGPoint(x: 100, y: 0.25), nearBottom = CGPoint(x: 100, y: 1.75)
      XCTAssertFalse(try path(growth.initialHeight).contains(nearTop))
      XCTAssertTrue(try path(growth.partialHeight).contains(nearTop))
      XCTAssertFalse(try path(growth.partialHeight).contains(nearBottom))
      XCTAssertTrue(try path(34).contains(nearBottom))
    }
  }

  func testTheKeyBackdropExtentIsTheMaskInsideTheBand() {
    let size = CGSize(width: 1512, height: 33)
    let mask = BarEntranceMask.band(elapsedMS: 180, bandSize: size, notchWidth: 150)
    let extent = BarEntranceMask.keyBackdropExtent(band: mask, bandSize: size)
    guard case .rect(let rect) = mask else { return XCTFail("Missing band mask") }
    XCTAssertLessThan(extent.width, size.width)
    // Intersecting the mask with the band can round its fractional edges.
    let accuracy: CGFloat = 1e-9 // points, well below one pixel
    XCTAssertEqual(extent.origin.x, rect.origin.x, accuracy: accuracy)
    XCTAssertEqual(extent.origin.y, rect.origin.y, accuracy: accuracy)
    XCTAssertEqual(extent.size.width, rect.size.width, accuracy: accuracy)
    XCTAssertEqual(extent.size.height, rect.size.height, accuracy: accuracy)
    let later = BarEntranceMask.band(elapsedMS: 300, bandSize: size, notchWidth: 150)
    XCTAssertGreaterThan(BarEntranceMask.keyBackdropExtent(band: later, bandSize: size).width, extent.width)
    let partial = BarMask.rect(CGRect(x: -10, y: 28, width: 40, height: 10))
    XCTAssertEqual(BarEntranceMask.keyBackdropExtent(band: partial, bandSize: size),
                   CGRect(x: 0, y: 28, width: 30, height: 5))
    let outside = BarMask.rect(CGRect(x: 1512, y: 0, width: 20, height: 10))
    XCTAssertEqual(BarEntranceMask.keyBackdropExtent(band: outside, bandSize: size), .zero)
    XCTAssertEqual(BarEntranceMask.keyBackdropExtent(band: .none, bandSize: size), CGRect(origin: .zero, size: size))
  }

  func testPathsAreOrientedForFlippedAndUnflippedLayers() throws {
    let rect = CGRect(x: 12, y: 2, width: 80, height: 5)
    for flipped in [true, false] {
      XCTAssertNil(BarEntranceMask.path(.none, height: 34, flipped: flipped))
      XCTAssertTrue(try XCTUnwrap(BarEntranceMask.path(.rect(.zero), height: 34, flipped: flipped)).isEmpty)
      let path = try XCTUnwrap(BarEntranceMask.path(.rect(rect), height: 34, flipped: flipped))
      XCTAssertEqual(path.boundingBoxOfPath, flipped ? rect : CGRect(x: 12, y: 27, width: 80, height: 5))
    }
  }
}
