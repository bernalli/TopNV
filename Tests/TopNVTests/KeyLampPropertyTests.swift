import AppKit
import XCTest

@testable import TopNV
@testable import TopNVCore

/// Hostile sequences of creations, gates, closes, Space changes, failed readbacks, lamp
/// errors and screen changes, in random scenes and appearances. After every step, each
/// live two-layer key has exactly one lamp with its alpha and mask, and no other lamp exists.
@MainActor
final class KeyLampPropertyTests: XCTestCase {
  private struct Generator {
    var seed: UInt64

    mutating func next(_ bound: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int((seed >> 33) % UInt64(bound))
    }

    mutating func pick<Value>(_ values: [Value]) -> Value { values[next(values.count)] }
  }

  /// What the plans commanded: the last gate of each live key and the mask of each display.
  private final class Model {
    var alpha: [Int: CGFloat] = [:]
    var display: [Int: UInt32] = [:]
    var mask: [UInt32: BarMask] = [1: BarMask.none, 2: BarMask.none]
    var jobOwners: [Int] = []
    var lit = 0
    var ordinary = 0
    /// Two-layer keys checked after a real Space exit or re-entry, and ordinary keys checked there.
    var exits = 0
    var entries = 0
    var spaceOrdinary = 0

    func live(on display: UInt32) -> [Int] {
      alpha.keys.filter { self.display[$0] == display }.sorted()
    }

    func forget(_ id: Int) {
      alpha[id] = nil
      display[id] = nil
    }
  }

  private static let entrance = BarMask.rect(CGRect(x: 20, y: 0, width: 80, height: 17))
  private static let masks: [BarMask] = [.none, .none, entrance, .rect(.zero)]
  private static let kinds = BarSceneKind.allCases.filter { $0 != .absent }
  private static let appearances: [KeyedOverlayState.Appearance] = [.light, .dark, .unknown]
  private static let gates: [BarAlpha] = [.value(0), .value(1), .value(1), .value(0.5), .hold]

  private var random = Generator(seed: 0x5DEE_CE66_D1CE_4E5B)
  private var harness: KeyHarness!
  private var model = Model()

  func testHostileSequencesKeepOneLampPerTwoLayerKeyWithItsAlphaAndMask() throws {
    var lit = 0
    var ordinary = 0
    var failures = 0
    var space = (exits: 0, entries: 0, ordinary: 0)
    for round in 0..<30 {
      harness = KeyHarness()
      model = Model()
      defer { harness.executor.closeAll() }
      for step in 0..<40 {
        let context = "round \(round) step \(step)"
        try perform()
        harness.closed.forEach(model.forget)
        if harness.executor.failed {
          checkFailSafe(context)
          failures += 1
          break
        }
        check(context)
      }
      lit += model.lit
      ordinary += model.ordinary
      space.exits += model.exits
      space.entries += model.entries
      space.ordinary += model.spaceOrdinary
    }
    XCTAssertGreaterThan(lit, 100)
    XCTAssertGreaterThan(ordinary, 20)
    XCTAssertGreaterThan(failures, 0)
    XCTAssertGreaterThan(space.exits, 0)
    XCTAssertGreaterThan(space.entries, 0)
    XCTAssertGreaterThanOrEqual(space.exits + space.entries, 20)
    XCTAssertGreaterThan(space.ordinary, 0)
  }

  private func perform() throws {
    let display = UInt32(1 + random.next(2))
    switch random.next(10) {
    case 0, 1: try create(on: display)
    case 2, 3: try gate(on: display)
    case 4:
      let close = model.live(on: display).filter { _ in random.next(2) == 0 }
      try send(ExecutorPlans.key(close: close, mask: random.pick(Self.masks)), to: display)
    case 5: try changeSpace(on: display)
    case 6: try corruptLamp(on: display)
    case 7: runJob()
    case 8: changeScreen(display)
    default: failDelayedRecommit()
    }
  }

  private func create(on display: UInt32) throws {
    guard model.live(on: display).count < 3 else { return }
    harness.rejectLamp = random.next(6) == 0
    harness.runtime.rejectPair = random.next(8) == 0
    let accepted = random.next(8) != 0
    harness.accept = { _, _, _ in accepted }
    defer {
      harness.rejectLamp = false
      harness.runtime.rejectPair = false
      harness.accept = { _, _, _ in true }
    }
    let id = harness.nextID
    let jobs = harness.jobs.count
    let plan = ExecutorPlans.key(create: try harness.creation(), mask: random.pick(Self.masks))
    try send(plan, to: display)
    model.jobOwners += Array(repeating: id, count: harness.jobs.count - jobs)
    if harness.ids.contains(id), !harness.closed.contains(id) {
      model.alpha[id] = 0
      model.display[id] = display
    }
  }

  private func gate(on display: UInt32) throws {
    var gates: [Int: BarAlpha] = [:]
    for id in model.live(on: display) where random.next(3) != 0 {
      gates[id] = random.pick(Self.gates)
    }
    try send(ExecutorPlans.key(gates: gates, mask: random.pick(Self.masks)), to: display)
  }

  /// A failed lamp readback reaches the executor at the next plan, on any display and scene.
  private func corruptLamp(on display: UInt32) throws {
    let lit = model.live(on: display).compactMap { harness.lamp.window(for: $0) }
    guard !lit.isEmpty else { return }
    let lamp = random.pick(lit)
    if random.next(2) == 0 { lamp.contentView = NSView() } else { lamp.orderOut(nil) }
    try send(ExecutorPlans.key(mask: random.pick(Self.masks)), to: display)
  }

  private func runJob() {
    guard !harness.jobs.isEmpty else { return }
    harness.runtime.rejectPairReadback = random.next(3) == 0
    defer { harness.runtime.rejectPairReadback = false }
    harness.jobs[random.next(harness.jobs.count)].run()
  }

  private func changeScreen(_ display: UInt32) {
    let frame = ExecutorPlans.frame
    var frames: [UInt32: CGRect] = [1: frame, 2: frame]
    var scales: [UInt32: CGFloat] = [:]
    if random.next(2) == 0 {
      scales[display] = 1
    } else {
      frames[display] = frame.offsetBy(dx: 0, dy: 1)
    }
    _ = harness.executor.closeChanged(frames: frames, enabled: random.next(8) != 0, scales: scales)
  }

  private func failDelayedRecommit() {
    let pending = model.jobOwners.indices.filter { model.alpha[model.jobOwners[$0]] != nil }
    guard random.next(4) == 0, !pending.isEmpty else { return }
    harness.runtime.fail = .recommit
    harness.jobs[random.pick(pending)].run()
    XCTAssertTrue(harness.executor.failed)
  }

  /// Both displays always receive a plan: a display missing from the plan closes its keys.
  private func send(_ key: BarKeyPlan, to display: UInt32) throws {
    let other: UInt32 = display == 1 ? 2 : 1
    var displays: [UInt32: BarDisplayPlan] = [:]
    for (id, part) in [(display, key), (other, ExecutorPlans.key())] {
      let appearance = random.pick(Self.appearances)
      displays[id] = ExecutorPlans.display(
        key: part, appearance: appearance, kind: random.pick(Self.kinds))
    }
    for id in key.close where model.display[id] == display { model.forget(id) }
    for (id, gate) in key.gates where model.display[id] == display {
      if case .value(let value) = gate { model.alpha[id] = value }
    }
    model.mask[display] = key.mask
    model.mask[other] = BarMask.none
    harness.executor.apply(BarPlan(displays: displays))
  }

  private func check(_ context: String) {
    var paired: Set<Int> = []
    for (index, id) in harness.ids.enumerated() {
      let key = harness.windows[index]
      let label = "\(context) key \(id)"
      guard let alpha = model.alpha[id], let display = model.display[id] else {
        XCTAssertNil(harness.lamp.window(for: id), label)
        XCTAssertFalse(key.isVisible, label)
        continue
      }
      XCTAssertEqual(key.alphaValue, alpha, label)
      guard let root = key.contentView?.layer else { return XCTFail(label) }
      let mask = model.mask[display] ?? BarMask.none
      let path = BarEntranceMask.path(
        mask, height: root.bounds.height, flipped: root.isGeometryFlipped)
      XCTAssertEqual((root.mask as? CAShapeLayer)?.path, path, label)
      let twoLayer = harness.runtime.pressedLayers.contains { $0.superlayer === root }
      let plate = root.sublayers?.first { $0.name == "Bottom plate" }
      XCTAssertEqual(plate?.frame.height, twoLayer ? 5 : 8.5, label)
      if twoLayer {
        paired.insert(id)
        model.lit += 1
        checkLamp(harness.lamp.window(for: id), of: key, mask: mask, label)
      } else {
        model.ordinary += 1
        XCTAssertNil(harness.lamp.window(for: id), "\(label): an ordinary key has a lamp")
      }
    }
    XCTAssertEqual(harness.lamp.keys, paired, context)
    let current = harness.lamp.keys.compactMap { harness.lamp.window(for: $0) }
    for window in harness.lampWindows where !current.contains(where: { $0 === window }) {
      XCTAssertFalse(window.isVisible, context)
      XCTAssertEqual(window.alphaValue, 0, context)
    }
  }

  private func checkLamp(
    _ lamp: OverlayWindow?, of key: OverlayWindow, mask: BarMask, _ label: String
  ) {
    guard let lamp else { return XCTFail("\(label): a two-layer key has no lamp") }
    XCTAssertEqual(lamp.alphaValue, key.alphaValue, label)
    XCTAssertTrue(lamp.isVisible, label)
    XCTAssertEqual(lamp.collectionBehavior, key.collectionBehavior, label)
    XCTAssertEqual(lamp.frame, key.frame, label)
    XCTAssertTrue((lamp.contentView as? BarStripView)?.matches(mask, in: lamp) == true, label)
  }

  private func checkFailSafe(_ context: String) {
    XCTAssertEqual(harness.lamp.keys, [], context)
    XCTAssertEqual(harness.failureCount, 1, context)
    for window in harness.windows + harness.lampWindows {
      XCTAssertFalse(window.isVisible, context)
      XCTAssertEqual(window.alphaValue, 0, context)
    }
    XCTAssertTrue(harness.runtime.pressedLayers.allSatisfy { $0.superlayer == nil }, context)
  }
}

/// The Space step: a plan right after an exit or a re-entry keeps each pair and each lamp.
private extension KeyLampPropertyTests {
  /// A key before a Space change: its pair object and its lamp window, by identity.
  struct SpaceSnapshot {
    let id: Int
    let key: OverlayWindow
    let wasActive: Bool
    let pair: AnyObject?
    let lamp: OverlayWindow?
  }

  /// A Space change moves every key of the display with its lamp. It leaves when a key is on the
  /// active Space and re-enters when none is, then a plan arrives at once: each two-layer key keeps
  /// the same pair object and the same lamp window, and an ordinary key gains no lamp.
  func changeSpace(on display: UInt32) throws {
    let indices = model.live(on: display).compactMap { harness.ids.firstIndex(of: $0) }
    guard !indices.isEmpty else { return }
    let leaving = indices.contains { harness.windows[$0].isOnActiveSpace }
    let before = indices.map { index in
      let key = harness.windows[index]
      return SpaceSnapshot(
        id: harness.ids[index], key: key, wasActive: key.isOnActiveSpace,
        pair: key.contentView?.layer.flatMap(harness.runtime.pair(on:)),
        lamp: harness.lamp.window(for: harness.ids[index]))
    }
    for index in indices {
      if leaving { harness.leaveSpace(index) } else { harness.enterSpace(index) }
    }
    try gate(on: display)
    harness.closed.forEach(model.forget)
    guard !harness.executor.failed else { return }
    for snapshot in before { checkSpace(snapshot, leaving: leaving) }
  }

  func checkSpace(_ before: SpaceSnapshot, leaving: Bool) {
    let label = "Space \(leaving ? "exit" : "entry") key \(before.id)"
    let key = before.key
    XCTAssertEqual(key.isOnActiveSpace, !leaving, label)
    let pair = key.contentView?.layer.flatMap(harness.runtime.pair(on:))
    let lamp = harness.lamp.window(for: before.id)
    guard let previous = before.pair else {
      XCTAssertNil(pair, "\(label): an ordinary key gained a pair")
      XCTAssertNil(lamp, "\(label): an ordinary key gained a lamp")
      model.spaceOrdinary += 1
      return
    }
    XCTAssertTrue(pair === previous, "\(label): the pair object changed")
    XCTAssertNotNil(before.lamp, label)
    XCTAssertTrue(lamp === before.lamp, "\(label): the lamp window changed")
    XCTAssertEqual(key.alphaValue, model.alpha[before.id], label)
    let mask = model.display[before.id].flatMap { model.mask[$0] } ?? BarMask.none
    checkLamp(lamp, of: key, mask: mask, label)
    guard before.wasActive == leaving else { return }
    if leaving { model.exits += 1 } else { model.entries += 1 }
  }
}
