import AppKit
import TopNVCore
import XCTest

@testable import TopNV

@MainActor
final class PreviewBandSurfaceTests: XCTestCase {
  func testKeyJoiningMidEntranceUsesTheCurrentBandWidthAndRestoresItsGate() throws {
    _ = NSApplication.shared
    let rect = CGRect(x: 0, y: 0, width: 1512, height: 33)
    let bar = BarWindow(frame: rect)
    let keyed = OverlayWindow(frame: rect, level: .normal, isOpaque: false, behavior: .transient)
    defer { bar.close(); keyed.close() }
    let view = NSView(frame: rect)
    view.wantsLayer = true
    keyed.contentView = view
    let root = try XCTUnwrap(view.layer)
    KeyedOverlayController.addBottomMask(to: root, size: rect.size, menuHeight: 33, scale: 2)
    let plate = try XCTUnwrap(root.sublayers?.first)
    let bottom = CGRect(x: 0, y: root.isGeometryFlipped ? 25.5 : 0, width: 1512, height: 7.5)
    XCTAssertEqual(plate.frame, bottom)
    let originalMask = CALayer()
    root.mask = originalMask
    let backdrop = CALayer()
    backdrop.frame = rect
    root.addSublayer(backdrop)
    let target = PreviewBandTarget(notchWidth: 150, bar: bar, keyed: nil, backdrops: [], corners: [:])
    let surface = PreviewBandSurface(target: target, variant: .calm)
    surface.draw(.calm, elapsed: 180)
    surface.includeKey(keyed, backdrops: [backdrop])
    surface.includeKey(keyed, backdrops: [backdrop])

    let band = try XCTUnwrap(bar.contentView?.layer?.sublayers?.first as? CAShapeLayer)
    let width = try XCTUnwrap(band.path).boundingBoxOfPath.width
    XCTAssertLessThan(width, rect.width)
    XCTAssertEqual(backdrop.frame.width, width, accuracy: 0.001)
    surface.draw(.calm, elapsed: 300)
    XCTAssertGreaterThan(backdrop.frame.width, width)
    XCTAssertEqual(plate.frame, bottom)

    keyed.alphaValue = 0
    surface.restore()
    XCTAssertTrue(root.mask === originalMask)
    XCTAssertEqual(backdrop.frame, rect)
    XCTAssertEqual(plate.frame, bottom)
    XCTAssertTrue(plate.superlayer === root)
    XCTAssertEqual(keyed.alphaValue, 0)
  }

  func testPauseTopStripAndInterruptionOnBothBandWindows() throws {
    _ = NSApplication.shared
    let rect = CGRect(x: 0, y: 0, width: 1000, height: 30)
    let bar = BarWindow(frame: rect)
    let keyed = OverlayWindow(frame: rect, level: .init(rawValue: 26), isOpaque: false, behavior: .transient)
    defer {
      bar.close()
      keyed.close()
    }
    let view = NSView(frame: rect)
    view.wantsLayer = true
    keyed.contentView = view
    let root = try XCTUnwrap(view.layer)
    let originalMask = CALayer()
    root.mask = originalMask
    let backdrops = [CALayer(), CALayer()]
    for layer in backdrops {
      layer.frame = rect
      root.addSublayer(layer)
    }
    let originalView = bar.contentView
    let target = PreviewBandTarget(notchWidth: 150, bar: bar, keyed: keyed, backdrops: backdrops, corners: [:])
    let surface = PreviewBandSurface(target: target, variant: .ink)
    surface.draw(.ink, elapsed: -1)
    XCTAssertFalse(bar.isOpaque)
    XCTAssertTrue(backdrops.allSatisfy { $0.frame.isEmpty })
    let keyedMask = try XCTUnwrap(root.mask as? CAShapeLayer)
    XCTAssertTrue(try XCTUnwrap(keyedMask.path).isEmpty)
    let band = try XCTUnwrap(bar.contentView?.layer?.sublayers?.first as? CAShapeLayer)
    XCTAssertTrue(try XCTUnwrap(band.path).isEmpty)

    surface.draw(.ink, elapsed: 426)
    let stripe = CGRect(x: 0, y: root.isGeometryFlipped ? 0 : 24.6, width: 1000, height: 5.4)
    for bounds in backdrops.map(\.frame) + [try XCTUnwrap(keyedMask.path).boundingBoxOfPath] {
      XCTAssertEqual(bounds.width, stripe.width, accuracy: 0.001)
      XCTAssertEqual(bounds.height, stripe.height, accuracy: 0.001)
      XCTAssertEqual(bounds.minY, stripe.minY, accuracy: 0.001)
    }
    XCTAssertEqual(try XCTUnwrap(band.path).boundingBoxOfPath.height, stripe.height, accuracy: 0.001)

    keyed.alphaValue = 0
    surface.restore()
    XCTAssertTrue(bar.isOpaque)
    XCTAssertEqual(bar.backgroundColor, .black)
    XCTAssertTrue(bar.contentView === originalView)
    XCTAssertTrue(root.mask === originalMask)
    XCTAssertTrue(backdrops.allSatisfy { $0.frame == rect })
    XCTAssertEqual(keyed.alphaValue, 0)
  }
}
