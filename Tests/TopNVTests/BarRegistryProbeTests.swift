import AppKit
import QuartzCore
import TopNVCore
import XCTest
@testable import TopNV

private struct WindowState: Equatable {
  let frame: CGRect
  let alpha: CGFloat
  let opaque: Bool
  let visible: Bool
  let view: ObjectIdentifier?
  let mask: ObjectIdentifier?

  @MainActor init(_ window: NSWindow) {
    frame = window.frame
    alpha = window.alphaValue
    opaque = window.isOpaque
    visible = window.isVisible
    view = window.contentView.map(ObjectIdentifier.init)
    mask = window.contentView?.layer?.mask.map(ObjectIdentifier.init)
  }
}

@MainActor
final class BarRegistryProbeTests: XCTestCase {
  private func keyWindow(frame: CGRect) -> OverlayWindow {
    let window = OverlayWindow(frame: frame, level: .init(rawValue: 26), isOpaque: false, behavior: .transient)
    let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
    view.wantsLayer = true
    window.contentView = view
    return window
  }

  private func cornerWindows(screen: NSScreen, display: UInt32) -> [String: CornerWindow] {
    let frames = ScreenGeometry.cornerRects(frame: screen.frame, radius: 15, topInset: 34)
    var corners: [String: CornerWindow] = [:]
    for (corner, rect) in frames {
      let window = CornerWindow(corner: corner, frame: rect)
      if corner != .bottomLeft { window.orderFrontRegardless() }
      corners["\(display).\(corner.rawValue)"] = window
    }
    return corners
  }

  func testProbeReadsEveryPartWithoutChangingIt() throws {
    _ = NSApplication.shared
    let screen = try XCTUnwrap(NSScreen.screens.first)
    let display = try XCTUnwrap(screen.displayID)
    let frame = CGRect(x: screen.frame.minX, y: screen.frame.maxY - 34, width: 240, height: 34)
    let bar = BarWindow(frame: frame)
    let key = keyWindow(frame: frame)
    defer { bar.close(); key.close() }
    bar.orderFrontRegardless()
    key.alphaValue = 0.5
    let root = try XCTUnwrap(key.contentView?.layer)
    KeyedOverlayController.addBottomMask(to: root, size: frame.size, menuHeight: 33, scale: 2)
    let strip = CGRect(x: frame.minX, y: frame.minY - 1, width: frame.width, height: 2)
    bar.menuEdge.update(frame: strip)
    let edge = try XCTUnwrap(bar.menuEdge.window)
    let corners = cornerWindows(screen: screen, display: display)
    defer { for corner in corners.values { corner.close() } }
    let windows: [OverlayWindow] = [bar, edge, key] + [CornerWindow](corners.values)
    let before = windows.map { WindowState($0) }
    let snapshot = BarRegistryProbe.snapshot(screens: [screen], bars: [display: bar], corners: corners,
                                             keys: [.init(display: display, window: key)], evidence: [:])
    XCTAssertEqual(windows.map { WindowState($0) }, before)
    XCTAssertEqual(snapshot.entries.count, 8)
    func entry(_ rect: CGRect, _ alpha: Double, _ level: Int, _ window: OverlayWindow,
               active: Bool = true) -> BarRegistryEntry {
      .init(pixels: BarPixels.pixels(rect, display: screen.frame, scale: screen.backingScaleFactor),
            alpha: alpha, level: level, window: window.windowNumber, mask: .none, onActiveSpace: active)
    }
    let bandLevel = Int(CGWindowLevelForKey(.desktopWindow)) + 1
    XCTAssertEqual(snapshot.entries[.init(display: display, part: .band)], entry(frame, 1, bandLevel, bar))
    let edgeEntry = entry(strip, 1, 27, edge)
    XCTAssertEqual(snapshot.entries[.init(display: display, part: .edge)], edgeEntry)
    XCTAssertEqual(snapshot.entries[.init(display: display, part: .key, keyWindow: key.windowNumber)],
                   entry(frame, 0.5, 26, key, active: key.isOnActiveSpace))
    let plate = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 8.5)
    XCTAssertEqual(snapshot.entries[.init(display: display, part: .plate, keyWindow: key.windowNumber)],
                   entry(plate, 0.5, 26, key, active: key.isOnActiveSpace))
    for (corner, rect) in ScreenGeometry.cornerRects(frame: screen.frame, radius: 15, topInset: 34) {
      let window = try XCTUnwrap(corners["\(display).\(corner.rawValue)"])
      XCTAssertEqual(snapshot.entries[.init(display: display, part: .corner(corner))],
                     entry(rect, corner == .bottomLeft ? 0 : 1, NSWindow.Level.popUpMenu.rawValue - 1, window))
    }
    XCTAssertEqual(snapshot.displays[display], .init(frame: screen.frame, scale: screen.backingScaleFactor,
                                                     scene: .unknown, bandEnabled: true,
                                                     blackBottom: try XCTUnwrap(edgeEntry.pixels).bottom))
  }

  func testProbeReportsTheEntranceMaskOfBandAndKey() throws {
    _ = NSApplication.shared
    let screen = try XCTUnwrap(NSScreen.screens.first)
    let display = try XCTUnwrap(screen.displayID)
    let frame = CGRect(x: screen.frame.minX + 20, y: screen.frame.maxY - 40, width: 800, height: 34)
    let bar = BarWindow(frame: frame)
    let key = keyWindow(frame: frame)
    defer { bar.close(); key.close() }
    let target = PreviewBandTarget(notchWidth: 100, bar: bar, keyed: key, backdrops: [], corners: [:])
    let surface = PreviewBandSurface(target: target, variant: .calm)
    let bandID = BarRegistryID(display: display, part: .band)
    let keyID = BarRegistryID(display: display, part: .key, keyWindow: key.windowNumber)
    func snapshot() -> BarRegistrySnapshot {
      BarRegistryProbe.snapshot(screens: [screen], bars: [display: bar], corners: [:],
                                keys: [.init(display: display, window: key)], evidence: [:])
    }
    surface.draw(.calm, elapsed: -1)
    let paused = snapshot()
    for id in [bandID, keyID] { XCTAssertEqual(paused.entries[id]?.mask, .empty) }
    surface.draw(.calm, elapsed: 180)
    let moving = snapshot()
    let band = try XCTUnwrap(moving.entries[bandID])
    guard case let .bounds(mask) = band.mask else { return XCTFail("Missing band mask bounds") }
    XCTAssertGreaterThan(mask.width, 0)
    XCTAssertLessThan(mask.width, try XCTUnwrap(band.pixels).width)
    XCTAssertEqual(moving.entries[keyID]?.mask, .bounds(mask))
    surface.restore()
    let restored = snapshot()
    for id in [bandID, keyID] { XCTAssertEqual(restored.entries[id]?.mask, BarMaskToken.none) }
  }
}
