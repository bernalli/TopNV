import AppKit
import XCTest
@testable import TopNV
@testable import TopNVCore

@MainActor
final class KeyLampTests: XCTestCase {
  func testLampFollowsAppliedAlphaAndEntranceMaskUntilSwitchedOff() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    harness.apply(ExecutorPlans.key(create: try harness.creation()))
    XCTAssertNil(harness.lamp.window(on: 1))
    XCTAssertTrue(harness.lampLines.isEmpty)
    harness.lampEnabled = true
    harness.apply(ExecutorPlans.key())
    let lamp = try XCTUnwrap(harness.lamp.window(on: 1))
    let key = try XCTUnwrap(harness.windows.first)
    XCTAssertEqual(lamp.alphaValue, 0)
    XCTAssertEqual(lamp.frame, ExecutorPlans.frame)
    XCTAssertTrue(lamp.isOpaque && lamp.ignoresMouseEvents)
    XCTAssertEqual(lamp.backgroundColor, .white)
    XCTAssertEqual(lamp.collectionBehavior, OverlayBehavior.bar)
    XCTAssertGreaterThan(lamp.level.rawValue, OverlayLevel.bar.rawValue)
    XCTAssertLessThan(lamp.level.rawValue, NSWindow.Level.mainMenu.rawValue)
    for gate: BarAlpha in [.value(1), .value(0.375), .hold, .value(0)] {
      harness.apply(ExecutorPlans.key(gates: [10: gate]))
      XCTAssertEqual(lamp.alphaValue, key.alphaValue)
    }

    let mask = BarMask.rect(CGRect(x: 20, y: 0, width: 80, height: 17))
    harness.apply(ExecutorPlans.key(gates: [10: .value(1)], mask: mask))
    XCTAssertEqual(lamp.alphaValue, key.alphaValue)
    let lampShape = try XCTUnwrap(lamp.contentView?.layer?.sublayers?.first as? CAShapeLayer)
    let keyShape = try XCTUnwrap(key.contentView?.layer?.mask as? CAShapeLayer)
    XCTAssertEqual(lampShape.path?.boundingBoxOfPath.size, keyShape.path?.boundingBoxOfPath.size)
    XCTAssertEqual(lampShape.fillColor, NSColor.white.cgColor)
    XCTAssertEqual(lamp.backgroundColor, .clear)
    let logged = harness.lampLines
    harness.apply(ExecutorPlans.key(mask: mask))
    XCTAssertEqual(harness.lampLines, logged)
    XCTAssertTrue(logged.last?.contains("px=0,0,400,68") == true)
    harness.lampEnabled = false
    harness.apply(ExecutorPlans.key())
    XCTAssertNil(harness.lamp.window(on: 1))
    XCTAssertEqual(lamp.alphaValue, 0)
    XCTAssertFalse(lamp.isVisible)
    XCTAssertEqual(key.alphaValue, 1)
  }

  func testHeldKeysCannotLightOtherScenesDarkMenusOrAnotherSpace() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    harness.lampEnabled = true
    harness.apply(ExecutorPlans.key(create: try harness.creation()))
    for kind: BarSceneKind in [.revealed, .overview, .sliding, .fullScreen, .absent, .unknown, .desktop] {
      harness.apply(ExecutorPlans.key(gates: [10: .value(1)]))
      let lamp = try XCTUnwrap(harness.lamp.window(on: 1))
      XCTAssertEqual(lamp.alphaValue, 1)
      let plan = ExecutorPlans.display(appearance: kind == .desktop ? .dark : .light, kind: kind)
      harness.executor.apply(BarPlan(displays: [1: plan]))
      XCTAssertNil(harness.lamp.window(on: 1))
      XCTAssertEqual(lamp.alphaValue, 0)
    }
    harness.leaveSpace(0)
    harness.apply(ExecutorPlans.key())
    XCTAssertEqual(harness.windows.first?.alphaValue, 1)
    XCTAssertEqual(harness.lamp.window(on: 1)?.alphaValue, 0)
  }

  func testClosingAnInactiveKeyPreservesTheLampUntilItsOwnerCloses() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    harness.lampEnabled = true
    let create = ExecutorPlans.key(create: try harness.creation())
    harness.apply(create)
    harness.apply(ExecutorPlans.key(gates: [10: .value(1)]))
    let lamp = try XCTUnwrap(harness.lamp.window(on: 1))
    harness.leaveSpace(0)
    harness.apply(create)
    XCTAssertEqual(lamp.alphaValue, 0)
    harness.apply(ExecutorPlans.key(gates: [11: .value(1)]))
    harness.apply(ExecutorPlans.key(close: [10]))
    XCTAssertTrue(harness.lamp.window(on: 1) === lamp)
    XCTAssertEqual(lamp.alphaValue, 1)
    harness.apply(ExecutorPlans.key(close: [11]))
    XCTAssertNil(harness.lamp.window(on: 1))
    XCTAssertEqual(lamp.alphaValue, 0)
    XCTAssertFalse(lamp.isVisible)
  }

  func testDelayedFailureClosesLitLampsOnBothDisplaysImmediately() throws {
    let harness = KeyHarness()
    harness.lampEnabled = true
    let create = ExecutorPlans.key(create: try harness.creation())
    harness.apply(create, second: create)
    harness.apply(ExecutorPlans.key(gates: [10: .value(1)]), second: ExecutorPlans.key(gates: [11: .value(0.5)]))
    let first = try XCTUnwrap(harness.lamp.window(on: 1))
    let second = try XCTUnwrap(harness.lamp.window(on: 2))
    XCTAssertEqual(first.alphaValue, 1)
    XCTAssertEqual(second.alphaValue, 0.5)
    harness.runtime.fail = .recommit
    harness.jobs[0].run()
    XCTAssertTrue(harness.executor.failed)
    for lamp in [first, second] {
      XCTAssertFalse(lamp.isVisible)
      XCTAssertEqual(lamp.alphaValue, 0)
    }
    XCTAssertNil(harness.lamp.window(on: 1))
    XCTAssertNil(harness.lamp.window(on: 2))
  }
}
