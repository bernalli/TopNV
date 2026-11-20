import AppKit
import XCTest
@testable import TopNV
@testable import TopNVCore

// Use literal commands so that these tests exercise only the executor.
enum ExecutorPlans {
  static let frame = CGRect(x: 100, y: 100, width: 200, height: 34)
  static let screen = BarDisplay(id: 1, frame: CGRect(x: 100, y: -66, width: 200, height: 200),
                                 visibleFrame: CGRect(x: 100, y: -66, width: 200, height: 167),
                                 safeAreaTop: 32, scale: 2, notchWidth: 60, isBuiltin: true)
  static func part(_ frame: CGRect? = ExecutorPlans.frame, alpha: BarAlpha = .value(1), mask: BarMask = .none,
                   exists: Bool = true) -> BarPartPlan {
    BarPartPlan(exists: exists, frame: frame, pixels: BarGeometry.pixels(frame, on: screen), alpha: alpha, mask: mask)
  }

  static func key(create: BarKeyCreation? = nil, gates: [Int: BarAlpha] = [:], close: [Int] = [],
                  mask: BarMask = .none, gap: CGFloat = 33) -> BarKeyPlan {
    let plate = BarGeometry.plate(keySize: frame.size, menuHeight: gap, scale: screen.scale)
    return BarKeyPlan(exists: true, frame: frame, plate: plate, gates: gates, close: close, create: create,
                      mask: mask, backdropExtent: mask == .none ? nil :
                        BarEntranceMask.keyBackdropExtent(band: mask, bandSize: frame.size))
  }

  static func display(band: BarPartPlan = part(), edge: BarPartPlan = part(), key: BarKeyPlan = ExecutorPlans.key(),
                      corners: [ScreenCorner: BarPartPlan] = [:], geometry: BarDisplay? = screen,
                      appearance: KeyedOverlayState.Appearance = .light,
                      kind: BarSceneKind = .desktop) -> BarDisplayPlan {
    BarDisplayPlan(geometry: geometry, appearance: appearance, kind: geometry == nil ? .absent : kind,
                   bandEnabled: band.exists,
                   band: band, edge: edge, key: key, corners: corners, blackBottom: 0)
  }

  @MainActor static func window(_ entry: BarRegistryEntry?) throws -> NSWindow {
    let number = try XCTUnwrap(entry?.window)
    return try XCTUnwrap(NSApp.window(withWindowNumber: number))
  }
}

@MainActor
final class BandExecutorTests: XCTestCase {
  private let id = BarRegistryID(display: 1, part: .band)

  func testAppliesFrameAlphaAndLevelWithOneWindowPerDisplay() throws {
    _ = NSApplication.shared
    let executor = BandExecutor()
    defer { executor.closeAll() }
    let first = ExecutorPlans.display()
    let initial = executor.apply(BarPlan(displays: [1: first, 2: first]))
    XCTAssertEqual(initial.count, 2)
    let window = try ExecutorPlans.window(initial[id])
    let moved = ExecutorPlans.frame.offsetBy(dx: 30, dy: -2)
    let updated = ExecutorPlans.display(band: ExecutorPlans.part(moved, alpha: .value(0.5)))
    let entries = executor.apply(BarPlan(displays: [1: updated]))
    XCTAssertEqual(entries.count, 1)
    XCTAssertTrue(try ExecutorPlans.window(entries[id]) === window)
    XCTAssertEqual(window.frame, moved)
    XCTAssertEqual(window.alphaValue, 0.5)
    XCTAssertEqual(entries[id]?.level, OverlayLevel.bar.rawValue)
    XCTAssertEqual(entries[id]?.pixels, PixelRect(x: 60, y: 4, width: 400, height: 68))
    let held = ExecutorPlans.display(band: ExecutorPlans.part(moved, alpha: .hold), geometry: nil)
    XCTAssertEqual(executor.apply(BarPlan(displays: [1: held]))[id]?.alpha, 0.5)
  }

  func testAMaskMakesTheBandClearAndNoMaskRestoresOpaqueBlack() throws {
    _ = NSApplication.shared
    let executor = BandExecutor()
    defer { executor.closeAll() }
    let solid = BarPlan(displays: [1: ExecutorPlans.display()])
    let window = try ExecutorPlans.window(executor.apply(solid)[id])
    let view = try XCTUnwrap(window.contentView)
    let shape = try XCTUnwrap(view.layer?.sublayers?.first as? CAShapeLayer)
    let rect = CGRect(x: 20, y: 0, width: 160, height: 8)
    let masked = ExecutorPlans.display(band: ExecutorPlans.part(mask: .rect(rect)))
    XCTAssertEqual(executor.apply(BarPlan(displays: [1: masked]))[id]?.mask,
                   .bounds(PixelRect(x: 40, y: 0, width: 320, height: 16)))
    XCTAssertFalse(window.isOpaque)
    XCTAssertEqual(window.backgroundColor, .clear)
    XCTAssertEqual(try XCTUnwrap(shape.path).boundingBoxOfPath.width, 160)
    _ = executor.apply(solid)
    XCTAssertTrue(window.contentView === view)
    XCTAssertTrue(window.isOpaque)
    XCTAssertEqual(window.backgroundColor, .black)
    XCTAssertNil(shape.path)
  }

  func testAPlanAppliedTwiceChangesNothing() throws {
    _ = NSApplication.shared
    let executor = BandExecutor()
    defer { executor.closeAll() }
    let plan = BarPlan(displays: [1: ExecutorPlans.display(band: ExecutorPlans.part(mask: .rect(.zero)))])
    let entries = executor.apply(plan)
    let window = try ExecutorPlans.window(entries[id])
    let view = window.contentView
    XCTAssertEqual(entries[id]?.mask, .empty)
    XCTAssertEqual(executor.apply(plan), entries)
    XCTAssertTrue(window.contentView === view)
    XCTAssertEqual(view?.layer?.sublayers?.count, 1)
  }

  func testAClosedBandHasNoWindow() throws {
    _ = NSApplication.shared
    let executor = BandExecutor()
    defer { executor.closeAll() }
    let window = try ExecutorPlans.window(executor.apply(BarPlan(displays: [1: ExecutorPlans.display()]))[id])
    let closed = ExecutorPlans.display(band: ExecutorPlans.part(nil, exists: false))
    XCTAssertTrue(executor.apply(BarPlan(displays: [1: closed])).isEmpty)
    XCTAssertFalse(window.isVisible)
  }
}
