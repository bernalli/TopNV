import AppKit
import XCTest
@testable import TopNV
@testable import TopNVCore

@MainActor
final class RecordingRuntime: KeyBackdropRuntime {
  enum Operation: String, Error, CaseIterable { case create, attach, flush, recommit, detach }
  var fail: Operation?
  var calls: [String] = []
  var layers: [CALayer] = []
  var recommitted: [CALayer] = []
  var cleanup: (() -> Void)?

  private func record(_ operation: Operation) throws {
    XCTAssertFalse(CATransaction.disableActions(), "Private calls must run outside the presentation transaction")
    calls.append(operation.rawValue)
    if operation == fail { throw operation }
  }

  func create(matrix: [Float], bounds: CGRect, scale: CGFloat, display: UInt32) throws -> CALayer {
    try record(.create)
    XCTAssertEqual(matrix, LuminanceKey.normal.matrix)
    XCTAssertEqual(scale, 2)
    let layer = CALayer()
    layer.frame = bounds
    layers.append(layer)
    return layer
  }

  func attach(root: CALayer, backdrop: CALayer) throws {
    root.addSublayer(backdrop)
    try record(.attach) // Includes failures after a partial attach.
  }

  func flush() throws { try record(.flush) }
  func recommit(_ backdrop: CALayer) throws {
    try record(.recommit)
    recommitted.append(backdrop)
  }

  func detach(_ backdrop: CALayer) throws {
    cleanup?()
    try record(.detach)
    backdrop.removeFromSuperlayer()
  }
}

@MainActor
private final class RecordingWindow: OverlayWindow {
  var active = true
  override var isOnActiveSpace: Bool { active }
  var record: ((String) -> Void)?
  override func orderFrontRegardless() {
    record?("order")
    super.orderFrontRegardless()
  }

  override func displayIfNeeded() {
    record?("display")
    super.displayIfNeeded()
  }
}

@MainActor
final class KeyHarness {
  let runtime = RecordingRuntime()
  var jobs: [(delay: Double, run: @MainActor () -> Void)] = []
  var windows: [OverlayWindow] = []
  var committed: [BarKeyCreation] = []
  var closed: [Int] = []
  var failureCount = 0
  var monitorStops = 0
  var lampPlate = LampPlatePreset.standard
  var lampOnly = false
  var lampEnabled = false
  var lampLines: [String] = []
  lazy var lamp = KeyLamp(enabled: { [unowned self] in lampEnabled },
                          only: { [unowned self] in lampOnly },
                          plate: { [unowned self] in lampPlate }, log: { [unowned self] in
    XCTAssertTrue(CATransaction.disableActions())
    lampLines.append($0)
  })
  var nextID = 10
  var accept: (BarKeyCreation, Int, UInt32) -> Bool = { _, _, _ in true }

  lazy var executor = KeyExecutor(runtime: runtime, lamp: lamp, schedule: { [unowned self] delay, run in
    jobs.append((delay, run))
  }, makeWindow: { [unowned self] frame in
    let window = RecordingWindow(frame: frame, level: .init(rawValue: 26), isOpaque: false,
                                 behavior: OverlayBehavior.keyed)
    window.record = { [weak runtime] in runtime?.calls.append($0) }
    windows.append(window)
    defer { nextID += 1 }
    return (nextID, window)
  }, keyCommitted: { [unowned self] creation, number, display in
    runtime.calls.append("commit")
    committed.append(creation)
    XCTAssertEqual(windows.last?.alphaValue, 0)
    XCTAssertFalse(windows.last?.isVisible == true)
    return accept(creation, number, display)
  }, keyClosed: { [unowned self] number, _ in closed.append(number) },
  keyDidFail: { [unowned self] in failureCount += 1 },
  stopAppearanceMonitor: { [unowned self] in monitorStops += 1 })

  init() { _ = NSApplication.shared }

  func leaveSpace(_ index: Int) { (windows[index] as? RecordingWindow)?.active = false }

  func creation() throws -> BarKeyCreation {
    var state = KeyedOverlayState()
    let decision = state.update(.init(activeWindowIDs: [], appearance: .light, context: .desktop,
                                      menuVisible: true, enabled: true, now: 1))
    return BarKeyCreation(instance: 7, reservation: try XCTUnwrap(decision.create))
  }

  @discardableResult
  func apply(_ key: BarKeyPlan, second: BarKeyPlan? = nil) -> [BarRegistryID: BarRegistryEntry] {
    var displays = [UInt32(1): ExecutorPlans.display(key: key)]
    if let second { displays[2] = ExecutorPlans.display(key: second) }
    return executor.apply(BarPlan(displays: displays))
  }
}

@MainActor
final class KeyExecutorTests: XCTestCase {
  func testAKeyCreatedMidEntranceTakesTheCurrentMaskAndKeepsItsPlate() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    let rect = CGRect(x: 22, y: 2, width: 80, height: 18)
    let masked = ExecutorPlans.key(create: try harness.creation(), mask: .rect(rect))
    let maskedEntries = harness.apply(masked)
    XCTAssertEqual(maskedEntries[.init(display: 1, part: .key, keyWindow: 10)]?.mask,
                   .bounds(PixelRect(x: 44, y: 4, width: 160, height: 36)))
    let root = try XCTUnwrap(harness.windows.first?.contentView?.layer)
    let plate = try XCTUnwrap(root.sublayers?.first { $0.name == "Bottom plate" })
    let original = plate.frame
    XCTAssertEqual(original, root.isGeometryFlipped ? masked.plate?.flipped : masked.plate?.unflipped)
    let expected = CGRect(x: 22, y: root.isGeometryFlipped ? 2 : 14, width: 80, height: 18)
    XCTAssertEqual(harness.runtime.layers.first?.frame, expected)
    XCTAssertEqual((root.mask as? CAShapeLayer)?.path?.boundingBoxOfPath, expected)
    let entries = harness.apply(ExecutorPlans.key(create: try harness.creation(), gates: [10: .value(1)],
                                                 mask: .rect(.zero), gap: 20))
    XCTAssertEqual(harness.windows.count, 2)
    for layer in harness.runtime.layers {
      XCTAssertEqual(layer.frame, .zero)
      XCTAssertTrue(((layer.superlayer?.mask as? CAShapeLayer)?.path)?.isEmpty == true)
    }
    XCTAssertEqual(entries[.init(display: 1, part: .plate, keyWindow: 10)]?.alpha, 1)
    XCTAssertEqual(entries[.init(display: 1, part: .key, keyWindow: 11)]?.alpha, 0)
    harness.apply(ExecutorPlans.key(gap: 20))
    for layer in harness.runtime.layers {
      let host = try XCTUnwrap(layer.superlayer)
      XCTAssertNil(host.mask)
      XCTAssertEqual(layer.frame, CGRect(origin: .zero, size: ExecutorPlans.frame.size))
    }
    XCTAssertEqual(plate.frame, original)
    XCTAssertTrue(plate.superlayer === root)
    XCTAssertEqual(plate.contentsScale, 2)
  }

  func testTheFailSafeClosesEveryKeyAndReportsOnce() throws {
    let failures = RecordingRuntime.Operation.allCases.map { ($0, 0) } + [(.recommit, 1)]
    for (operation, timerIndex) in failures {
      let harness = KeyHarness()
      let create = ExecutorPlans.key(create: try harness.creation())
      harness.apply(create, second: create)
      guard harness.jobs.count == 4 else { return XCTFail("Expected two timers for each key") }
      if timerIndex == 1 { harness.jobs[0].run() }
      harness.runtime.fail = operation
      // A cleanup failure must never re-enter the fail-safe.
      var cleaningAfterFailure = false
      harness.runtime.cleanup = { [weak harness] in
        guard let harness, harness.executor.failed else { return }
        cleaningAfterFailure = true
        harness.runtime.fail = .detach
      }
      switch operation {
      case .create, .attach, .flush: harness.apply(create, second: create)
      case .detach: harness.apply(ExecutorPlans.key(close: [10]), second: ExecutorPlans.key())
      case .recommit: harness.jobs[timerIndex].run()
      }
      XCTAssertTrue(cleaningAfterFailure, operation.rawValue)
      XCTAssertTrue(harness.executor.failed, operation.rawValue)
      XCTAssertEqual(harness.failureCount, 1)
      XCTAssertEqual(harness.monitorStops, 1)
      XCTAssertTrue(harness.windows.allSatisfy { !$0.isVisible })
      let calls = harness.runtime.calls
      let jobs = harness.jobs
      XCTAssertEqual(jobs.count, 4)
      for job in jobs { job.run() }
      XCTAssertTrue(harness.apply(create).isEmpty)
      harness.executor.closeAll()
      XCTAssertEqual(harness.runtime.calls, calls)
      XCTAssertEqual(harness.failureCount, 1)
    }
  }

  func testAConsumedReservationIsNotCreatedTwice() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    var state = KeyedOverlayState()
    let decision = state.update(.init(activeWindowIDs: [], appearance: .light, context: .desktop,
                                      menuVisible: true, enabled: true, now: 1))
    let creation = BarKeyCreation(instance: 9, reservation: try XCTUnwrap(decision.create))
    harness.accept = { received, number, display in
      XCTAssertEqual(display, 1)
      XCTAssertEqual(received, creation)
      return state.commit(received.reservation, windowID: number)
    }
    let create = ExecutorPlans.key(create: creation)
    let first = harness.apply(create)
    XCTAssertEqual(harness.apply(create), first)
    XCTAssertEqual(harness.committed, [creation, creation])
    XCTAssertFalse(try XCTUnwrap(harness.windows.last).isVisible)
    XCTAssertEqual(harness.runtime.calls.filter { $0 == "flush" }.count, 1)
    XCTAssertEqual(harness.jobs.count, 2)
  }

  func testGatesSetAlphaAndHoldKeepsIt() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    harness.apply(ExecutorPlans.key(create: try harness.creation()))
    let window = try XCTUnwrap(harness.windows.first)
    let expectedIDs = window.isOnActiveSpace ? [10] : []
    XCTAssertEqual(harness.executor.activeWindowIDs(display: 1), expectedIDs)
    XCTAssertEqual(harness.executor.activeWindowIDs(display: 2), [])
    for (gate, alpha): (BarAlpha, CGFloat) in [(.value(1), 1), (.hold, 1), (.value(0), 0), (.hold, 0)] {
      harness.apply(ExecutorPlans.key(gates: [10: gate]))
      XCTAssertEqual(window.alphaValue, alpha)
      harness.apply(ExecutorPlans.key())
      XCTAssertEqual(window.alphaValue, alpha)
    }
  }

  func testAFrameOrScaleChangeClosesAndReportsTheDisplay() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    let create = ExecutorPlans.key(create: try harness.creation())
    let frame = ExecutorPlans.frame
    let frames: [UInt32: CGRect] = [1: frame, 2: frame]
    harness.apply(create, second: create)
    XCTAssertEqual(harness.executor.closeChanged(frames: frames, enabled: true, scales: [:]), [])
    XCTAssertEqual(harness.executor.closeChanged(frames: frames, enabled: true, scales: [2: 1]), [2])
    let moved = [UInt32(1): frame.offsetBy(dx: 1, dy: 0)]
    XCTAssertEqual(harness.executor.closeChanged(frames: moved, enabled: true, scales: [:]), [1])
    harness.apply(create)
    XCTAssertEqual(harness.executor.closeChanged(frames: frames, enabled: false, scales: [:]), [1])
    XCTAssertEqual(harness.closed, [11, 10, 12])
  }

  func testFlushSchedulesExactlyTwoRecommitsForTheAttachedWindow() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    harness.apply(ExecutorPlans.key(create: try harness.creation()))
    let calls = harness.runtime.calls
    let attach = try XCTUnwrap(calls.firstIndex(of: "attach"))
    let commit = try XCTUnwrap(calls.firstIndex(of: "commit"))
    let order = try XCTUnwrap(calls.firstIndex(of: "order"))
    let display = try XCTUnwrap(calls[order...].firstIndex(of: "display"))
    let flush = try XCTUnwrap(calls.firstIndex(of: "flush"))
    XCTAssertLessThan(attach, commit)
    XCTAssertLessThan(commit, order)
    XCTAssertLessThan(order, display)
    XCTAssertLessThan(display, flush)
    XCTAssertEqual(harness.jobs.map(\.delay), [0.25, 1.0])
    for job in harness.jobs { job.run() }
    XCTAssertEqual(harness.runtime.recommitted.count, 2)
    XCTAssertTrue(harness.runtime.recommitted.allSatisfy { $0 === harness.runtime.layers.first })
    XCTAssertEqual(harness.jobs.count, 2)
  }

  func testLateRecommitsIgnoreClosedWindowsAndReusedNumbers() throws {
    let harness = KeyHarness()
    defer { harness.executor.closeAll() }
    let create = ExecutorPlans.key(create: try harness.creation())
    harness.apply(create)
    let oldJobs = harness.jobs
    harness.executor.closeAll()
    for job in oldJobs { job.run() }
    harness.nextID = 10
    harness.apply(create)
    XCTAssertEqual(harness.windows.count, 2)
    XCTAssertFalse(harness.windows.first === harness.windows.last)
    for job in oldJobs { job.run() }
    XCTAssertTrue(harness.runtime.recommitted.isEmpty)
    for job in harness.jobs.dropFirst(oldJobs.count) { job.run() }
    XCTAssertEqual(harness.runtime.recommitted.count, 2)
    XCTAssertTrue(harness.runtime.recommitted.allSatisfy { $0 === harness.runtime.layers.last })
  }
}
