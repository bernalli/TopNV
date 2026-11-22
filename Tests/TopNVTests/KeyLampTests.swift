import AppKit
import XCTest

@testable import TopNV
@testable import TopNVCore

@MainActor
final class KeyLampTests: XCTestCase {
  private let litMask = BarMask.rect(CGRect(x: 20, y: 0, width: 80, height: 17))

  func testNormalWindowShadowsStayBelowTheLampAndSystemRevealsStayAboveIt() {
    XCTAssertGreaterThan(KeyLamp.level.rawValue, NSWindow.Level.normal.rawValue)
    XCTAssertLessThan(KeyLamp.level.rawValue, BarSceneKind.overviewLayer - 1)
    XCTAssertLessThan(KeyLamp.level.rawValue, NSWindow.Level.mainMenu.rawValue)
  }

  func testTheLampWindowBelongsToOneSpaceLikeItsKeyAndSitsBelowIt() {
    _ = NSApplication.shared
    let lamp = KeyLamp.makeWindow(ExecutorPlans.frame)
    defer { lamp.close() }
    XCTAssertEqual(lamp.collectionBehavior, OverlayBehavior.keyed)
    XCTAssertEqual(KeyLamp.behavior, OverlayBehavior.keyed)
    XCTAssertFalse(lamp.collectionBehavior.contains(.canJoinAllSpaces))
    XCTAssertTrue(lamp.isOpaque && lamp.ignoresMouseEvents)
    XCTAssertEqual(lamp.level, KeyLamp.level)
    XCTAssertGreaterThan(lamp.level.rawValue, OverlayLevel.bar.rawValue)
    XCTAssertLessThan(lamp.level.rawValue, MenuBarEvidence.overlayLevel)
    XCTAssertLessThan(lamp.level.rawValue, NSWindow.Level.mainMenu.rawValue)
  }

  func testEachTwoLayerKeyIsCreatedWithItsOwnLampOnItsSpace() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    harness.apply(ExecutorPlans.key(create: try harness.creation(), mask: litMask))
    let key = try XCTUnwrap(harness.windows.first)
    let lamp = try XCTUnwrap(harness.lamp.window(for: 10))
    XCTAssertEqual(harness.lamp.keys, [10])
    XCTAssertEqual(lamp.collectionBehavior, key.collectionBehavior)
    XCTAssertTrue(lamp.isVisible)
    XCTAssertEqual(lamp.alphaValue, 0)
    XCTAssertEqual(lamp.frame, key.frame)
    XCTAssertEqual(lamp.backgroundColor, .clear)
    // The lamp is ordered in with its key, before the flush: both join the Space active at creation.
    let calls = harness.runtime.calls
    let commit = try XCTUnwrap(calls.firstIndex(of: "commit"))
    let lampOrder = try XCTUnwrap(calls.firstIndex(of: "lamp order"))
    let keyOrder = try XCTUnwrap(calls.firstIndex(of: "order"))
    let flush = try XCTUnwrap(calls.firstIndex(of: "flush"))
    XCTAssertLessThan(commit, lampOrder)
    XCTAssertLessThan(lampOrder, keyOrder)
    XCTAssertLessThan(keyOrder, flush)
    XCTAssertEqual(calls.filter { $0 == "lamp order" }.count, 1)
    let lampShape = try XCTUnwrap(lamp.contentView?.layer?.sublayers?.first as? CAShapeLayer)
    let keyShape = try XCTUnwrap(key.contentView?.layer?.mask as? CAShapeLayer)
    XCTAssertEqual(lampShape.path?.boundingBoxOfPath.size, keyShape.path?.boundingBoxOfPath.size)
    XCTAssertEqual(lampShape.fillColor, NSColor.white.cgColor)
  }

  func testTheLampTakesItsKeysAlphaAndMaskInEveryPlan() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    harness.apply(ExecutorPlans.key(create: try harness.creation()))
    let lamp = try XCTUnwrap(harness.lamp.window(for: 10))
    let key = try XCTUnwrap(harness.windows.first)
    XCTAssertEqual(lamp.backgroundColor, .white)
    for gate: BarAlpha in [.value(1), .value(0.375), .hold, .value(0)] {
      harness.apply(ExecutorPlans.key(gates: [10: gate]))
      XCTAssertEqual(lamp.alphaValue, key.alphaValue)
    }
    let entries = harness.apply(ExecutorPlans.key(gates: [10: .value(1)], mask: litMask))
    let registered = try XCTUnwrap(entries[.init(display: 1, part: .lamp, keyWindow: 10)])
    XCTAssertNil(entries[.init(display: 1, part: .lamp)])
    XCTAssertEqual(registered.window, lamp.windowNumber)
    XCTAssertEqual(registered.alpha, 1)
    XCTAssertEqual(registered.mask, entries[.init(display: 1, part: .key, keyWindow: 10)]?.mask)
    XCTAssertEqual(lamp.alphaValue, key.alphaValue)
    XCTAssertEqual(lamp.backgroundColor, .clear)
    XCTAssertEqual(harness.runtime.pressedLayers.first?.frame, harness.runtime.layers.first?.frame)
    let logged = harness.lampLines
    harness.apply(ExecutorPlans.key(mask: litMask))
    XCTAssertEqual(harness.lampLines, logged)
    XCTAssertTrue(logged.last { $0.hasPrefix("Lamp ") }?.contains("key=10") == true)
    XCTAssertTrue(logged.last { $0.hasPrefix("Lamp ") }?.contains("px=0,0,400,68") == true)
  }

  func testTwoActiveKeysHaveTwoLampsEachWithTheAlphaOfItsKey() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    let create = ExecutorPlans.key(create: try harness.creation())
    harness.apply(create, second: create)
    harness.apply(create, second: ExecutorPlans.key())
    harness.apply(
      ExecutorPlans.key(gates: [10: .value(1), 12: .value(0.5)]),
      second: ExecutorPlans.key(gates: [11: .value(0.25)]))
    XCTAssertEqual(harness.lamp.keys, [10, 11, 12])
    let lamps = try [10, 11, 12].map { try XCTUnwrap(harness.lamp.window(for: $0)) }
    XCTAssertEqual(Set(lamps.map { ObjectIdentifier($0) }).count, 3)
    XCTAssertEqual(lamps.map(\.alphaValue), [1, 0.25, 0.5])
    XCTAssertEqual(harness.windows.map(\.alphaValue), [1, 0.25, 0.5])
  }

  func testASlideKeepsTheFrozenGatesAndEachLampFollowsItsKey() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    let create = ExecutorPlans.key(create: try harness.creation())
    harness.apply(create)
    harness.apply(ExecutorPlans.key(gates: [10: .value(1)]))
    harness.leaveSpace(0)
    harness.apply(create)
    let leaving = try XCTUnwrap(harness.lamp.window(for: 10))
    let arriving = try XCTUnwrap(harness.lamp.window(for: 11))
    // No gate command: the scene froze both gates, so both Spaces keep drawing during the slide.
    for kind: BarSceneKind in [.sliding, .fullScreen, .unknown, .revealed, .overview, .desktop] {
      for appearance: KeyedOverlayState.Appearance in [.light, .dark, .unknown] {
        let plan = ExecutorPlans.display(appearance: appearance, kind: kind)
        harness.executor.apply(BarPlan(displays: [1: plan]))
        XCTAssertEqual(harness.windows.map(\.alphaValue), [1, 0], "\(kind) \(appearance)")
        XCTAssertEqual(leaving.alphaValue, 1, "\(kind) \(appearance)")
        XCTAssertEqual(arriving.alphaValue, 0, "\(kind) \(appearance)")
      }
    }
    harness.enterSpace(0)
    harness.executor.apply(
      BarPlan(displays: [
        1: ExecutorPlans.display(
          key: ExecutorPlans.key(gates: [10: .value(0), 11: .value(1)]), appearance: .dark,
          kind: .sliding)
      ]))
    XCTAssertEqual(harness.windows.map(\.alphaValue), [0, 1])
    XCTAssertEqual(leaving.alphaValue, 0)
    XCTAssertEqual(arriving.alphaValue, 1)
  }

  func testClosingAKeyClosesOnlyItsOwnLamp() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    let create = ExecutorPlans.key(create: try harness.creation())
    harness.apply(create)
    harness.apply(ExecutorPlans.key(gates: [10: .value(1)]))
    harness.leaveSpace(0)
    harness.apply(create)
    harness.apply(ExecutorPlans.key(gates: [11: .value(1)]))
    let first = try XCTUnwrap(harness.lamp.window(for: 10))
    let second = try XCTUnwrap(harness.lamp.window(for: 11))
    harness.apply(ExecutorPlans.key(close: [10]))
    XCTAssertNil(harness.lamp.window(for: 10))
    XCTAssertFalse(first.isVisible)
    XCTAssertEqual(first.alphaValue, 0)
    XCTAssertTrue(harness.lamp.window(for: 11) === second)
    XCTAssertEqual(second.alphaValue, 1)
    XCTAssertTrue(second.isVisible)
    harness.apply(ExecutorPlans.key(close: [11]))
    XCTAssertEqual(harness.lamp.keys, [])
    XCTAssertFalse(second.isVisible)
  }

  func testAScaleOrFrameChangeAndTheFailSafeCloseTheLamps() throws {
    let harness = KeyHarness()
    let create = ExecutorPlans.key(create: try harness.creation())
    harness.apply(create, second: create)
    harness.apply(
      ExecutorPlans.key(gates: [10: .value(1)]), second: ExecutorPlans.key(gates: [11: .value(0.5)])
    )
    let first = try XCTUnwrap(harness.lamp.window(for: 10))
    let second = try XCTUnwrap(harness.lamp.window(for: 11))
    let frame = ExecutorPlans.frame
    XCTAssertEqual(
      harness.executor.closeChanged(frames: [1: frame, 2: frame], enabled: true, scales: [2: 1]),
      [2])
    XCTAssertNil(harness.lamp.window(for: 11))
    XCTAssertFalse(second.isVisible)
    XCTAssertEqual(second.alphaValue, 0)
    XCTAssertTrue(first.isVisible)
    XCTAssertEqual(first.alphaValue, 1)
    harness.apply(create, second: create)
    let third = try XCTUnwrap(harness.lamp.window(for: 12))
    harness.runtime.fail = .recommit
    harness.jobs[0].run()
    XCTAssertTrue(harness.executor.failed)
    XCTAssertTrue(harness.runtime.pressedLayers.allSatisfy { $0.superlayer == nil })
    for lamp in [first, second, third] {
      XCTAssertFalse(lamp.isVisible)
      XCTAssertEqual(lamp.alphaValue, 0)
    }
    XCTAssertEqual(harness.lamp.keys, [])
  }

  func testConfirmedDepthUpdatesThePlateWithoutReplacingTheKey() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    harness.runtime.rejectPair = true
    harness.apply(ExecutorPlans.key(create: try harness.creation(), confirmedMenuDepth: 31))
    let key = try XCTUnwrap(harness.windows.first)
    let plate = try XCTUnwrap(key.contentView?.layer?.sublayers?.first { $0.name == "Bottom plate" })
    XCTAssertEqual(plate.frame.height, 10.5)

    harness.apply(ExecutorPlans.key(confirmedMenuDepth: 32))
    XCTAssertEqual(plate.frame.height, 9.5)
    XCTAssertEqual(harness.windows.count, 1)

    harness.apply(ExecutorPlans.key())
    XCTAssertEqual(plate.frame.height, 8.5)
    harness.apply(ExecutorPlans.key(gap: 20))
    XCTAssertEqual(plate.frame.height, 8.5)
  }

  func testConfirmedDepthUpdatesTheCalibratedPlate() throws {
    let initial = ExecutorPlans.key(confirmedMenuDepth: 31)
    let plate = KeyBottomPlate(original: try XCTUnwrap(initial.plate),
                               calibrated: try XCTUnwrap(initial.calibratedPlate), menuDepth: 31)
    let root = CALayer()
    plate.install(in: root, scale: 2)
    plate.apply(calibrated: true)
    XCTAssertEqual(plate.layer.frame.height, 7)

    plate.update(ExecutorPlans.key(confirmedMenuDepth: 32), calibrated: true)
    XCTAssertEqual(plate.layer.frame.height, 6)
    plate.update(ExecutorPlans.key(), calibrated: true)
    XCTAssertEqual(plate.layer.frame.height, 5)
    plate.update(ExecutorPlans.key(gap: 20), calibrated: true)
    XCTAssertEqual(plate.layer.frame.height, 5)
    XCTAssertTrue(plate.layer.superlayer === root)
  }

  func testPairAndLampFailuresRestoreTheOrdinaryKeyAndCreationPlate() throws {
    for failure in ["lamp", "lamp readback", "lamp out", "pair", "pair readback"] {
      let harness = KeyHarness()
      defer { harness.executor.closeAll() }
      harness.rejectLamp = failure == "lamp"
      harness.runtime.rejectPair = failure == "pair"
      harness.apply(ExecutorPlans.key(create: try harness.creation()))
      harness.apply(ExecutorPlans.key(gates: [10: .value(1)]))
      let key = try XCTUnwrap(harness.windows.first)
      let plate = try XCTUnwrap(
        key.contentView?.layer?.sublayers?.first { $0.name == "Bottom plate" })
      switch failure {
      case "lamp readback":
        XCTAssertEqual(plate.frame.height, 5)
        try XCTUnwrap(harness.lamp.window(for: 10)).contentView = NSView()
        harness.jobs[0].run()
      case "lamp out":
        let lamp = try XCTUnwrap(harness.lamp.window(for: 10))
        lamp.orderOut(nil)
        harness.apply(ExecutorPlans.key())
        XCTAssertFalse(lamp.isVisible, failure)
      case "pair readback":
        XCTAssertEqual(plate.frame.height, 5)
        harness.runtime.rejectPairReadback = true
        harness.jobs[0].run()
      default: break
      }
      harness.apply(ExecutorPlans.key())
      XCTAssertNil(harness.lamp.window(for: 10), failure)
      XCTAssertEqual(harness.lamp.keys, [], failure)
      XCTAssertEqual(key.alphaValue, 1, failure)
      XCTAssertEqual(plate.frame.height, 8.5, failure)
      XCTAssertTrue(harness.runtime.pressedLayers.allSatisfy { $0.superlayer == nil }, failure)
      XCTAssertTrue(
        harness.runtime.recommitted.contains { $0 === harness.runtime.layers.first }, failure)
      XCTAssertFalse(harness.executor.failed, failure)
    }
  }
}
