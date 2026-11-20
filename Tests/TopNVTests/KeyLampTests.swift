import AppKit
import XCTest
@testable import TopNV
@testable import TopNVCore

@MainActor
final class KeyLampTests: XCTestCase {
  func testLampFollowsAppliedAlphaAndEntranceMask() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    harness.apply(ExecutorPlans.key(create: try harness.creation()))
    let lamp = try XCTUnwrap(harness.lamp.window(on: 1))
    let key = try XCTUnwrap(harness.windows.first)
    XCTAssertEqual(lamp.alphaValue, 0)
    let pressed = try XCTUnwrap(harness.runtime.pressedLayers.first)
    XCTAssertTrue(pressed.superlayer === key.contentView?.layer)
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
    let entries = harness.apply(ExecutorPlans.key(gates: [10: .value(1)], mask: mask))
    let registered = try XCTUnwrap(entries[.init(display: 1, part: .lamp)])
    XCTAssertEqual(registered.window, lamp.windowNumber)
    XCTAssertEqual(registered.mask, entries[.init(display: 1, part: .key, keyWindow: 10)]?.mask)
    XCTAssertEqual(lamp.alphaValue, key.alphaValue)
    let lampShape = try XCTUnwrap(lamp.contentView?.layer?.sublayers?.first as? CAShapeLayer)
    let keyShape = try XCTUnwrap(key.contentView?.layer?.mask as? CAShapeLayer)
    XCTAssertEqual(lampShape.path?.boundingBoxOfPath.size, keyShape.path?.boundingBoxOfPath.size)
    XCTAssertEqual(pressed.frame, harness.runtime.layers.first?.frame)
    XCTAssertEqual(lampShape.fillColor, NSColor.white.cgColor)
    XCTAssertEqual(lamp.backgroundColor, .clear)
    let logged = harness.lampLines
    harness.apply(ExecutorPlans.key(mask: mask))
    XCTAssertEqual(harness.lampLines, logged)
    XCTAssertTrue(logged.last { $0.hasPrefix("Lamp ") }?.contains("px=0,0,400,68") == true)
    harness.executor.closeAll()
    XCTAssertNil(harness.lamp.window(on: 1))
    XCTAssertEqual(lamp.alphaValue, 0)
    XCTAssertFalse(lamp.isVisible)
    XCTAssertEqual(key.alphaValue, 0)
  }

  func testPairAndLampFailuresRestoreTheOrdinaryKeyAndCreationPlate() throws {
    for failure in ["lamp creation", "lamp readback", "pair creation", "pair readback"] {
      let harness = KeyHarness()
      defer { harness.executor.closeAll() }
      harness.rejectLamp = failure == "lamp creation"
      harness.runtime.rejectPair = failure == "pair creation"
      harness.apply(ExecutorPlans.key(create: try harness.creation()))
      harness.apply(ExecutorPlans.key(gates: [10: .value(1)]))
      let key = try XCTUnwrap(harness.windows.first)
      let plate = try XCTUnwrap(key.contentView?.layer?.sublayers?.first { $0.name == "Bottom plate" })
      if failure.hasSuffix("readback") {
        XCTAssertEqual(plate.frame.height, 5)
        if failure == "lamp readback" {
          let lamp = try XCTUnwrap(harness.lamp.window(on: 1))
          lamp.contentView = NSView()
          harness.jobs[0].run()
        } else {
          harness.runtime.rejectPairReadback = true
          harness.jobs[0].run()
        }
      }
      harness.apply(ExecutorPlans.key())
      XCTAssertNil(harness.lamp.window(on: 1), failure)
      XCTAssertEqual(key.alphaValue, 1, failure)
      XCTAssertEqual(plate.frame.height, 8.5, failure)
      XCTAssertTrue(harness.runtime.pressedLayers.allSatisfy { $0.superlayer == nil }, failure)
      XCTAssertTrue(harness.runtime.recommitted.contains { $0 === harness.runtime.layers.first }, failure)
      XCTAssertFalse(harness.executor.failed, failure)
    }
  }

  func testHeldKeysCannotLightOtherScenesDarkMenusOrAnotherSpace() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    harness.apply(ExecutorPlans.key(create: try harness.creation()))
    for kind: BarSceneKind in [.revealed, .overview, .sliding, .fullScreen, .absent, .unknown, .desktop] {
      harness.apply(ExecutorPlans.key(gates: [10: .value(1)]))
      let lamp = try XCTUnwrap(harness.lamp.window(on: 1))
      XCTAssertEqual(lamp.alphaValue, 1)
      let plan = ExecutorPlans.display(appearance: kind == .desktop ? .dark : .light, kind: kind)
      harness.executor.apply(BarPlan(displays: [1: plan]))
      XCTAssertNil(harness.lamp.window(on: 1))
      XCTAssertEqual(lamp.alphaValue, 0)
      XCTAssertEqual(harness.windows.first?.alphaValue, 0)
    }
    harness.leaveSpace(0)
    harness.apply(ExecutorPlans.key())
    XCTAssertEqual(harness.windows.first?.alphaValue, 0)
    XCTAssertNil(harness.lamp.window(on: 1))
  }

  func testClosingAnInactiveKeyPreservesTheLampUntilItsOwnerCloses() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
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
    XCTAssertTrue(harness.runtime.pressedLayers.allSatisfy { $0.superlayer == nil })
    for lamp in [first, second] {
      XCTAssertFalse(lamp.isVisible)
      XCTAssertEqual(lamp.alphaValue, 0)
    }
    XCTAssertNil(harness.lamp.window(on: 1))
    XCTAssertNil(harness.lamp.window(on: 2))
  }
}
