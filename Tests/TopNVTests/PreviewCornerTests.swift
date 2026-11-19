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
      let end = BarAnimation.calm.durationMS
      // The band arrives at 72% of the duration; the corners fade in after it.
      let arrival = end * 0.72
      for (elapsed, opacity) in [(-1.0, CGFloat(0)), (0, 0), (arrival - 1, 0), (end, 1), (end + 5000, 1)] {
        preview.draw(.calm, at: elapsed)
        XCTAssertEqual(window.alphaValue, opacity, "\(corner.rawValue) at \(elapsed)")
        XCTAssertTrue(window.contentView === original)
      }
      preview.draw(.calm, at: (arrival + end) / 2)
      XCTAssertGreaterThan(window.alphaValue, 0, corner.rawValue)
      XCTAssertLessThan(window.alphaValue, 1, corner.rawValue)
      preview.draw(.calm, at: arrival / 2)
      XCTAssertEqual(window.alphaValue, 0, corner.rawValue)

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
    surface.draw(.calm, elapsed: 480)
    XCTAssertGreaterThan(window.alphaValue, 0)
    XCTAssertLessThan(window.alphaValue, 1)
    window.desktopVisible = false
    surface.restore()
    XCTAssertEqual(window.alphaValue, 0)
    window.desktopVisible = true
    XCTAssertEqual(window.alphaValue, 1)
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
