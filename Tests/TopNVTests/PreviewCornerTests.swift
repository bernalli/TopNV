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

  private func checkAnchors(_ variant: BarAnimation, at elapsed: Double,
                            flippedParent: Bool = false) throws {
    _ = NSApplication.shared
    for corner in ScreenCorner.allCases {
      let frame = CGRect(x: 0, y: 0, width: 15, height: 15)
      let window = CornerWindow(corner: corner, frame: frame)
      let original = window.contentView
      let preview = PreviewCorner(corner: corner, window: window)
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
