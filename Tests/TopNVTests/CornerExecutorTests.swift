import AppKit
import XCTest
@testable import TopNV
@testable import TopNVCore

@MainActor
final class CornerExecutorTests: XCTestCase {
  private func parts(alpha: Double) -> [ScreenCorner: BarPartPlan] {
    let frames = ScreenGeometry.cornerRects(frame: ExecutorPlans.screen.frame, radius: 15, topInset: 34)
    return frames.mapValues { ExecutorPlans.part($0, alpha: .value(alpha)) }
  }

  func testCornersTakeFrameAndAlphaFromThePlan() throws {
    _ = NSApplication.shared
    let executor = CornerExecutor()
    defer { executor.closeAll() }
    let corners = parts(alpha: 0.25)
    let entries = executor.apply(BarPlan(displays: [1: ExecutorPlans.display(corners: corners)]))
    XCTAssertEqual(entries.count, 4)
    for (corner, part) in corners {
      let entry = entries[BarRegistryID(display: 1, part: .corner(corner))]
      let window = try ExecutorPlans.window(entry)
      XCTAssertEqual(window.frame, part.frame)
      XCTAssertEqual(window.alphaValue, 0.25)
      XCTAssertEqual(entry?.level, OverlayLevel.corner.rawValue)
      XCTAssertEqual(entry?.pixels, part.pixels)
    }
  }

  func testCornersOfAClosedDisplayCloseAndAHeldDisplayKeepsThem() throws {
    _ = NSApplication.shared
    let executor = CornerExecutor()
    defer { executor.closeAll() }
    let corners = parts(alpha: 0.25)
    let display = ExecutorPlans.display(corners: corners)
    let initial = executor.apply(BarPlan(displays: [1: display, 2: display]))
    let windows = try initial.mapValues { try ExecutorPlans.window($0) }
    let held = corners.mapValues { _ in ExecutorPlans.part(nil, alpha: .value(1)) }
    let remaining = executor.apply(BarPlan(displays: [1: ExecutorPlans.display(corners: held, geometry: nil)]))
    XCTAssertEqual(remaining.count, 4)
    for (id, window) in windows {
      if id.display == 1, case let .corner(corner) = id.part {
        XCTAssertEqual(remaining[id]?.window, initial[id]?.window)
        XCTAssertEqual(window.frame, corners[corner]?.frame)
        XCTAssertEqual(window.alphaValue, 1)
      } else {
        XCTAssertNil(remaining[id])
        XCTAssertFalse(window.isVisible)
      }
    }
  }
}
