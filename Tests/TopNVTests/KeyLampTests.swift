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
    XCTAssertTrue(logged.last { $0.hasPrefix("Lamp ") }?.contains("px=0,0,400,68") == true)
    harness.lampEnabled = false
    harness.apply(ExecutorPlans.key())
    XCTAssertNil(harness.lamp.window(on: 1))
    XCTAssertEqual(lamp.alphaValue, 0)
    XCTAssertFalse(lamp.isVisible)
    XCTAssertEqual(key.alphaValue, 1)
  }

  func testLitPlatesChangeOnLiveKeysAndRestoreTheirCreationFrames() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    let create = ExecutorPlans.key(create: try harness.creation())
    let live = ExecutorPlans.key(gates: [10: .value(1)])
    harness.lampPlate = LampPlatePreset.choices[4]
    harness.apply(create)
    harness.apply(live)
    let root = try XCTUnwrap(harness.windows.first?.contentView?.layer)
    let plate = try XCTUnwrap(root.sublayers?.first { $0.name == "Bottom plate" })
    let original = plate.frame
    XCTAssertEqual(original.height, 8.5)
    harness.lampEnabled = true
    let rows: [Int?] = [51, 56, 60, 64, nil]
    let margins = ["7.5", "5", "3", "1", "none"]
    XCTAssertEqual(LampPlatePreset.choices.count, rows.count)
    for (index, preset) in LampPlatePreset.choices.enumerated() {
      harness.lampPlate = preset
      harness.apply(live)
      let row = rows[index]
      XCTAssertEqual(plate.frame.height, row.map { CGFloat(68 - $0) / 2 } ?? 0)
      XCTAssertEqual(plate.frame.minY, root.isGeometryFlipped ? 34 - plate.frame.height : 0)
      let line = "LampPlate voce=\(index + 1) margin=\(margins[index]) px=\(row.map(String.init) ?? "none")"
      XCTAssertTrue(harness.lampLines.contains(line))
    }
    harness.lampOnly = true
    harness.apply(live)
    XCTAssertEqual(plate.frame, original)
    harness.lampOnly = false
    harness.apply(live)
    XCTAssertEqual(plate.frame.height, 0)
    harness.lampEnabled = false
    harness.apply(ExecutorPlans.key(gap: 20))
    XCTAssertEqual(plate.frame, original)
    XCTAssertTrue(plate.superlayer === root)
    XCTAssertEqual(harness.windows.count, 1)
  }

  func testLampOnlyClosesTheKeyAndRestoresTheLatestHeldGate() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    harness.lampEnabled = true
    harness.apply(ExecutorPlans.key(create: try harness.creation()))
    harness.apply(ExecutorPlans.key(gates: [10: .value(1)]))
    let lamp = try XCTUnwrap(harness.lamp.window(on: 1))
    let key = try XCTUnwrap(harness.windows.first)
    harness.lampOnly = true
    harness.apply(ExecutorPlans.key())
    XCTAssertTrue(harness.lamp.window(on: 1) === lamp)
    XCTAssertEqual(lamp.alphaValue, 1)
    XCTAssertEqual(key.alphaValue, 0)
    harness.apply(ExecutorPlans.key(gates: [10: .value(0.5)]))
    XCTAssertEqual(lamp.alphaValue, 0.5)
    XCTAssertEqual(key.alphaValue, 0)
    harness.lampOnly = false
    harness.apply(ExecutorPlans.key(gates: [10: .hold]))
    XCTAssertEqual(key.alphaValue, 0.5)
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
