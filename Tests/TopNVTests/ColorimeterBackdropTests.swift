import AppKit
import BackdropRuntime
import TopNVCore
import XCTest
@testable import TopNV

/// A solid swatch below both siblings distinguishes shared input from feedback:
/// on black G is white, and on white G is black. Observe the upper layer's *input*.
@MainActor final class ColorimeterBackdropTests: XCTestCase {
  private final class Reader: NSObject, CALayerDelegate {
    let receive: @MainActor @Sendable (Double) -> Void
    init(_ receive: @escaping @MainActor @Sendable (Double) -> Void) { self.receive = receive }

    @objc(backdropLayer:didChangeLuma:)
    func changed(_ layer: CALayer, luma: Double) {
      DispatchQueue.main.async { [receive] in receive(luma) }
    }
  }

  func testUpperInputFollowsTheSwatchAcrossBothGlyphPolarities() async throws {
    _ = NSApplication.shared
    let frame = CGRect(x: 80, y: 80, width: 96, height: 48)
    let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
    view.wantsLayer = true
    window.contentView = view
    let root = try XCTUnwrap(view.layer)
    let swatch = CALayer()
    swatch.frame = root.bounds
    swatch.backgroundColor = NSColor.black.cgColor
    root.addSublayer(swatch)
    var reason: NSString?
    let glyph = try XCTUnwrap(KOCreateBackdrop(LuminanceKey.normal.matrix, 20, root.bounds, 1, &reason))
    root.addSublayer(glyph)
    let original = try XCTUnwrap(glyph.filters?.first as? NSObject)
    let pair: KeyBackdropPair
    do {
      pair = try PrivateBackdropRuntime().installPair(on: glyph)
    } catch {
      throw XCTSkip("Grouped backdrops unavailable: \(error)")
    }
    try pair.verifyCommit()
    let upper = try XCTUnwrap(root.sublayers?.last)
    XCTAssertFalse(upper === glyph)
    XCTAssertEqual(upper.value(forKey: "groupName") as? String, glyph.value(forKey: "groupName") as? String)
    XCTAssertEqual((upper.compositingFilter as? NSObject)?.value(forKey: "type") as? String, "lightenBlendMode")
    try await verifyInputs(upper, swatch: swatch) { window.orderFrontRegardless() }
    upper.compositingFilter = nil
    XCTAssertThrowsError(try pair.verifyCommit())
    pair.remove()
    try PrivateBackdropRuntime().recommit(glyph)
    XCTAssertTrue((glyph.filters?.first as? NSObject) === original)
    XCTAssertEqual(root.sublayers, [swatch, glyph])
    XCTAssertEqual(glyph.filters?.count, 1)
  }

  private func verifyInputs(_ upper: CALayer, swatch: CALayer, present: () -> Void) async throws {
    let black = expectation(description: "Upper samples black underneath white glyph output")
    let white = expectation(description: "Upper samples white underneath black glyph output")
    var dark = true
    let reader = Reader { luma in
      if dark && luma < 0.1 { black.fulfill() }
      if !dark && luma > 0.9 { white.fulfill() }
    }
    black.assertForOverFulfill = false
    white.assertForOverFulfill = false
    guard upper.responds(to: NSSelectorFromString("setTracksLuma:")),
          upper.responds(to: NSSelectorFromString("setAllowsFilteredLuma:")) else {
      throw XCTSkip("Render server input-luma callbacks unavailable")
    }
    upper.delegate = reader
    defer {
      upper.delegate = nil
      withExtendedLifetime(reader) {}
    }
    upper.setValue(false, forKey: "allowsFilteredLuma")
    upper.setValue(true, forKey: "tracksLuma")
    present()
    CATransaction.flush()
    await fulfillment(of: [black], timeout: 3)
    dark = false
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    swatch.backgroundColor = NSColor.white.cgColor
    CATransaction.commit()
    CATransaction.flush()
    await fulfillment(of: [white], timeout: 3)
  }
}
