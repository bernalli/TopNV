import AppKit
import TopNVCore
import XCTest
@testable import TopNV

@MainActor
final class MenuEdgeCoverTests: XCTestCase {
  func testIndependentOpaqueCoverFollowsTheBandAnimationAndClosesWithItsBar() throws {
    _ = NSApplication.shared
    let bar = BarWindow(frame: CGRect(x: 100, y: 100, width: 200, height: 34))
    defer { bar.close() }
    let edge = CGRect(x: 100, y: 99, width: 200, height: 2)
    bar.menuEdge.update(frame: edge, windows: nil)
    let cover = try XCTUnwrap(bar.menuEdge.window)
    XCTAssertEqual(cover.frame, edge)
    XCTAssertGreaterThan(cover.level.rawValue, MenuBarEvidence.overlayLevel)
    XCTAssertLessThan(cover.level.rawValue, NSWindow.Level.popUpMenu.rawValue)
    XCTAssertTrue(cover.ignoresMouseEvents)
    XCTAssertTrue(cover.isOpaque)
    XCTAssertEqual(cover.backgroundColor, .black)

    let target = PreviewBandTarget(notchWidth: 50, bar: bar, keyed: nil, backdrops: [], corners: [:])
    let surface = PreviewBandSurface(target: target, variant: .calm)
    surface.draw(.calm, elapsed: -1)
    XCTAssertFalse(cover.isOpaque)
    let shape = try XCTUnwrap(cover.contentView?.layer?.sublayers?.first as? CAShapeLayer)
    XCTAssertTrue(try XCTUnwrap(shape.path).isEmpty)
    surface.draw(.calm, elapsed: 180)
    let path = try XCTUnwrap(shape.path)
    XCTAssertLessThan(path.boundingBoxOfPath.width, edge.width)
    XCTAssertTrue(path.contains(CGPoint(x: edge.width / 2, y: edge.height / 2)))
    surface.restore()
    XCTAssertTrue(cover.isOpaque)
    XCTAssertEqual(cover.backgroundColor, .black)
    bar.menuEdge.update(frame: nil, windows: nil)
    XCTAssertFalse(cover.isVisible)
    bar.close()
    XCTAssertNil(bar.menuEdge.window)
  }

  func testStripGrowsFromItsTopEdgeDuringVerticalBandGrowth() throws {
    _ = NSApplication.shared
    let bar = BarWindow(frame: CGRect(x: 100, y: 100, width: 200, height: 34))
    defer { bar.close() }
    struct GrowthCase {
      let edgeOrigin: CGFloat
      let initialHeight: CGFloat
      let partialHeight: CGFloat
    }
    let growthCases = [
      GrowthCase(edgeOrigin: 99, initialHeight: 32.5, partialHeight: 33.5),
      GrowthCase(edgeOrigin: 98, initialHeight: 31.5, partialHeight: 33),
      GrowthCase(edgeOrigin: 97, initialHeight: 31.5, partialHeight: 33)
    ]
    for growth in growthCases {
      let edge = CGRect(x: 100, y: growth.edgeOrigin, width: 200, height: 2)
      bar.menuEdge.update(frame: edge, windows: nil)
      let root = try XCTUnwrap(bar.menuEdge.window?.contentView?.layer)
      let shape = try XCTUnwrap(root.sublayers?.first as? CAShapeLayer)
      let nearTop = CGPoint(x: 100, y: root.isGeometryFlipped ? 0.25 : 1.75)
      let nearBottom = CGPoint(x: 100, y: root.isGeometryFlipped ? 1.75 : 0.25)
      let initial = CGPath(rect: CGRect(x: 0, y: 0, width: 200, height: growth.initialHeight), transform: nil)
      bar.menuEdge.draw(initial, in: bar.frame)
      XCTAssertFalse(shape.path?.contains(nearTop) == true, "strip starts at \(edge.maxY)")

      let partial = CGPath(rect: CGRect(x: 0, y: 0, width: 200, height: growth.partialHeight), transform: nil)
      bar.menuEdge.draw(partial, in: bar.frame)
      let growingPath = try XCTUnwrap(shape.path)
      XCTAssertTrue(growingPath.contains(nearTop), "strip starts at \(edge.maxY)")
      XCTAssertFalse(growingPath.contains(nearBottom), "strip starts at \(edge.maxY)")

      let full = CGPath(rect: CGRect(x: 0, y: 0, width: 200, height: 34), transform: nil)
      bar.menuEdge.draw(full, in: bar.frame)
      XCTAssertTrue(try XCTUnwrap(shape.path).contains(nearBottom))
    }
  }
}
