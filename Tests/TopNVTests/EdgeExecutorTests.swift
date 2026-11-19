import AppKit
import XCTest
@testable import TopNV
@testable import TopNVCore

@MainActor
final class EdgeExecutorTests: XCTestCase {
  private let id = BarRegistryID(display: 1, part: .edge)
  private let frame = CGRect(x: 100, y: 99, width: 200, height: 2)

  private func plan(_ part: BarPartPlan) -> BarPlan {
    BarPlan(displays: [1: ExecutorPlans.display(edge: part)])
  }

  func testTheEdgeIsOpaqueBlackAboveTheKeyAndBelowPopUpMenus() throws {
    _ = NSApplication.shared
    let executor = EdgeExecutor()
    defer { executor.closeAll() }
    let entries = executor.apply(plan(ExecutorPlans.part(frame)))
    let window = try ExecutorPlans.window(entries[id])
    XCTAssertTrue(window.isOpaque)
    XCTAssertEqual(window.backgroundColor, .black)
    XCTAssertTrue(window.ignoresMouseEvents)
    XCTAssertEqual(window.collectionBehavior, OverlayBehavior.bar)
    XCTAssertEqual(window.frame, frame)
    XCTAssertEqual(window.level.rawValue, MenuBarEvidence.overlayLevel + 1)
    XCTAssertLessThan(window.level.rawValue, NSWindow.Level.popUpMenu.rawValue)
    XCTAssertEqual(entries[id]?.pixels, PixelRect(x: 0, y: 66, width: 400, height: 4))
  }

  func testAHiddenEdgeIsOrderedOutAndAClosedEdgeHasNoWindow() throws {
    _ = NSApplication.shared
    let executor = EdgeExecutor()
    defer { executor.closeAll() }
    let hidden = plan(ExecutorPlans.part(nil, alpha: .value(0)))
    XCTAssertTrue(executor.apply(hidden).isEmpty)
    let window = try ExecutorPlans.window(executor.apply(plan(ExecutorPlans.part(frame)))[id])
    let retained = executor.apply(hidden)
    XCTAssertEqual(retained[id]?.alpha, 0)
    XCTAssertEqual(retained[id]?.window, window.windowNumber)
    XCTAssertFalse(window.isVisible)
    let moved = frame.offsetBy(dx: 20, dy: 0)
    XCTAssertTrue(try ExecutorPlans.window(executor.apply(plan(ExecutorPlans.part(moved)))[id]) === window)
    XCTAssertEqual(window.frame, moved)
    XCTAssertTrue(window.isVisible)
    XCTAssertTrue(executor.apply(plan(ExecutorPlans.part(nil, exists: false))).isEmpty)
    XCTAssertFalse(window.isVisible)
  }

  func testAnEdgeMaskMakesTheWindowClearAndBack() throws {
    _ = NSApplication.shared
    let executor = EdgeExecutor()
    defer { executor.closeAll() }
    let masked = plan(ExecutorPlans.part(frame, mask: .rect(CGRect(x: 40, y: 0, width: 80, height: 1))))
    let entries = executor.apply(masked)
    let window = try ExecutorPlans.window(entries[id])
    let view = window.contentView
    let shape = try XCTUnwrap(view?.layer?.sublayers?.first as? CAShapeLayer)
    XCTAssertEqual(entries[id]?.mask, .bounds(PixelRect(x: 80, y: 66, width: 160, height: 2)))
    XCTAssertFalse(window.isOpaque)
    XCTAssertEqual(window.backgroundColor, .clear)
    XCTAssertNotNil(shape.path)
    _ = executor.apply(plan(ExecutorPlans.part(frame)))
    XCTAssertTrue(window.contentView === view)
    XCTAssertTrue(window.isOpaque)
    XCTAssertEqual(window.backgroundColor, .black)
    XCTAssertNil(shape.path)
  }
}
