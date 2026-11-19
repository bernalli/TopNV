import AppKit
import TopNVCore
import XCTest

@testable import TopNV

@MainActor
final class PreviewCornerTests: XCTestCase {
  func testGrowingCornersStayAttachedToTheirScreenVertices() throws {
    try checkAnchors(.arrows, at: 510)
  }

  func testUnfoldingCornersStayAttachedToTheirScreenEdges() throws {
    try checkAnchors(.blind, at: 700)
  }

  func testGrowingCornersStayAttachedWithFlippedParentGeometry() throws {
    try checkAnchors(.arrows, at: 510, flippedParent: true)
  }

  /// The production entrance fades the corners in place. An interruption leaves them opaque.
  func testCalmCornersFadeInPlaceAndAnInterruptionRestoresThem() throws {
    _ = NSApplication.shared
    for corner in ScreenCorner.allCases {
      let window = CornerWindow(corner: corner, frame: CGRect(x: 0, y: 0, width: 15, height: 15))
      defer { window.close() }
      let original = window.contentView
      let preview = PreviewCorner(corner: corner, window: window, variant: .calm)
      let arrival = 410.4
      for (elapsed, opacity) in [(-1.0, CGFloat(0)), (0, 0), (arrival, 1), (arrival + 5000, 1)] {
        preview.draw(.calm, at: elapsed)
        XCTAssertEqual(window.alphaValue, opacity, "\(corner.rawValue) at \(elapsed)")
        XCTAssertTrue(window.contentView === original)
      }
      preview.draw(.calm, at: arrival / 2)
      XCTAssertGreaterThan(window.alphaValue, 0, corner.rawValue)
      XCTAssertLessThan(window.alphaValue, 1, corner.rawValue)

      preview.restore()
      XCTAssertTrue(window.contentView === original)
      XCTAssertEqual(window.alphaValue, 1, corner.rawValue)
    }
  }

  func testCalmEntranceControlsTheVisibleWindowThroughTheLastFrame() {
    _ = NSApplication.shared
    let frame = CGRect(x: 0, y: 0, width: 15, height: 15)
    let window = CornerWindow(corner: .topLeft, frame: frame)
    defer { window.close() }
    let bar = BarWindow(frame: frame)
    defer { bar.close() }
    let target = PreviewBandTarget(notchWidth: 4, bar: bar, keyed: nil, backdrops: [], corners: [.topLeft: window])
    let surface = PreviewBandSurface(target: target, variant: .calm)
    surface.draw(.calm, elapsed: 0)
    window.desktopVisible = true
    XCTAssertEqual(window.alphaValue, 0)
    surface.draw(.calm, elapsed: 205.2)
    XCTAssertGreaterThan(window.alphaValue, 0)
    XCTAssertLessThan(window.alphaValue, 1)
    window.desktopVisible = false
    surface.restore()
    XCTAssertEqual(window.alphaValue, 0)
    window.desktopVisible = true
    XCTAssertEqual(window.alphaValue, 1)
  }

  func testEveryCornerFadesWithTheDrawnBandFromTheFirstFrameToItsArrival() throws {
    _ = NSApplication.shared
    let bar = BarWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 30))
    let rect = CGRect(x: 0, y: 0, width: 15, height: 15)
    let corners = Dictionary(uniqueKeysWithValues: ScreenCorner.allCases.map {
      ($0, CornerWindow(corner: $0, frame: rect))
    })
    defer {
      bar.close()
      for window in corners.values { window.close() }
    }
    let target = PreviewBandTarget(notchWidth: 150, bar: bar, keyed: nil, backdrops: [], corners: corners)
    let surface = PreviewBandSurface(target: target, variant: .calm)
    defer { surface.restore() }
    let band = try XCTUnwrap(bar.contentView?.layer?.sublayers?.first as? CAShapeLayer)
    for elapsed in Array(stride(from: 0.0, to: 410.4, by: 1000.0 / 60)) + [410.4, 570] {
      surface.draw(.calm, elapsed: elapsed)
      let width = try XCTUnwrap(band.path).boundingBoxOfPath.width
      // The band starts at 128 points on this screen and reaches both edges at 1000.
      let fraction = (width - 128) / (1000 - 128)
      let alphas = ScreenCorner.allCases.compactMap { corners[$0]?.alphaValue }
      print("cornerFrame trackMS=\(elapsed) bandWidth=\(width) alpha=\(alphas)")
      for (corner, window) in corners {
        XCTAssertEqual(window.alphaValue, fraction, accuracy: 0.00001, "\(corner) at \(elapsed) ms")
      }
    }
  }

  private func checkAnchors(_ variant: BarAnimation, at elapsed: Double,
                            flippedParent: Bool = false) throws {
    _ = NSApplication.shared
    for corner in ScreenCorner.allCases {
      let frame = CGRect(x: 0, y: 0, width: 15, height: 15)
      let window = CornerWindow(corner: corner, frame: frame)
      let original = window.contentView
      let preview = PreviewCorner(corner: corner, window: window, variant: variant)
      defer { window.close() }
      let parent = try XCTUnwrap(window.contentView?.layer)
      let drawing = try XCTUnwrap(original?.layer)
      parent.isGeometryFlipped = flippedParent
      let top = corner == .topLeft || corner == .topRight
      let left = corner == .topLeft || corner == .bottomLeft
      let initial = CGPoint(x: left ? parent.bounds.minX : parent.bounds.maxX,
                            y: top == flippedParent ? parent.bounds.minY : parent.bounds.maxY)
      let vertex = drawing.convert(initial, from: parent)

      preview.draw(variant, at: elapsed)

      let animated = drawing.convert(vertex, to: parent)
      XCTAssertEqual(animated.x, initial.x, accuracy: 0.001, corner.rawValue)
      XCTAssertEqual(animated.y, initial.y, accuracy: 0.001, corner.rawValue)
      XCTAssertLessThan(drawing.affineTransform().d, 1, corner.rawValue)
      XCTAssertGreaterThan(drawing.affineTransform().d, 0, corner.rawValue)

      preview.restore()
      XCTAssertTrue(window.contentView === original)
    }
  }
}
