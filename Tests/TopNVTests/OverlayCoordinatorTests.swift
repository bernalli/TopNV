import AppKit
import XCTest
import TopNVCore
@testable import TopNV

@MainActor
private final class Samples: BarSampling {
  var onSample: (() -> Void)?
  var screens: [BarDisplay] = []
  var windows: [MenuBarEvidence.Window]?
  var now = 1.0
  var reduced = true
  var fullScreen = false
  var fast = false
  var monitoring = false
  var events: [String] = []

  func sampleNow() -> BarSample {
    events.append("list")
    return .init(displays: screens, windows: windows, systemFullScreen: fullScreen, appearance: [1: .light, 2: .light],
                 activeKeyWindows: [:], now: now, reduceMotion: reduced, signalTime: now)
  }

  func monitorAppearance(_ enabled: Bool) { monitoring = enabled }
  func scheduleSamples(needed: Bool, duringReveal: Bool) { fast = needed && duringReveal }
}

@MainActor
private final class Parts: BarPartExecuting {
  let parts: [BarPart]
  var plans: [BarPlan] = []
  var duringApply: (() -> Void)?

  init(_ parts: [BarPart]) { self.parts = parts }

  func apply(_ plan: BarPlan) -> BarEntries {
    plans.append(plan)
    let callback = duringApply
    duringApply = nil
    callback?()
    var entries: BarEntries = [:]
    for (id, display) in plan.displays {
      for (index, part) in parts.enumerated() {
        let value: BarPartPlan?
        let number: Int
        switch part {
        case .band: value = display.band; number = 1
        case .edge: value = display.edge; number = 2
        case let .corner(corner): value = display.corners[corner]; number = 3 + index
        default: continue
        }
        guard let value, value.exists else { continue }
        let alpha: Double
        if case let .value(applied) = value.alpha { alpha = applied } else { alpha = 1 }
        entries[.init(display: id, part: part)] = .init(
          pixels: value.pixels, alpha: alpha, level: 26, window: Int(id) * 10 + number,
          mask: value.mask == .none ? .none : .empty, onActiveSpace: true)
      }
    }
    return entries
  }

  func closeAll() {}
}

@MainActor
private final class Keys: BarKeyExecuting {
  let samples: Samples
  weak var controller: OverlayController?
  var active: [UInt32: [Int]] = [:]
  var closed: Set<UInt32> = []
  var creations: [BarKeyCreation] = []
  var windows: [UInt32: [Int: Double]] = [:]
  var plans: [BarPlan] = []
  init(_ samples: Samples) { self.samples = samples }

  func closeChanged(frames: [UInt32: CGRect], enabled: Bool, scales: [UInt32: CGFloat]) -> Set<UInt32> {
    samples.events.append("closeChanged")
    for id in closed {
      active[id] = nil
      for number in windows.removeValue(forKey: id)?.keys.map({ $0 }) ?? [] {
        controller?.keyClosed(window: number, display: id)
      }
    }
    defer { closed.removeAll() }
    return closed
  }

  func activeWindowIDs(display: UInt32) -> [Int] {
    samples.events.append("active \(display)")
    return active[display] ?? []
  }

  func apply(_ plan: BarPlan) -> BarEntries {
    samples.events.append("keys")
    plans.append(plan)
    var entries: BarEntries = [:]
    for id in plan.displays.keys.sorted() {
      guard let display = plan.displays[id], display.key.exists else {
        windows[id] = nil
        continue
      }
      let key = display.key
      for number in key.close {
        windows[id]?[number] = nil
        controller?.keyClosed(window: number, display: id)
      }
      for (number, alpha) in key.gates where windows[id]?[number] != nil {
        if case let .value(value) = alpha { windows[id]?[number] = value }
      }
      if let creation = key.create {
        creations.append(creation)
        let number = 100 + creations.count
        XCTAssertTrue(controller?.keyCommitted(creation, window: number, display: id) == true)
        windows[id, default: [:]][number] = 0
      }
      for (number, alpha) in windows[id] ?? [:] {
        for part in [BarPart.key, .plate] {
          entries[.init(display: id, part: part, keyWindow: number)] = .init(
            pixels: display.band.pixels, alpha: alpha, level: 26, window: number,
            mask: key.mask == .none ? .none : .empty, onActiveSpace: active[id]?.contains(number) == true)
        }
      }
    }
    return entries
  }

  func closeAll() {}
}

@MainActor
private final class Clock: EntranceTiming {
  var frame: ((Double) -> Void)?
  var finish: (() -> Void)?
  var ends: [Double] = []
  var cancelled = false

  func start(_ entrance: BarEntrance, returnSignal: Double?, onFrame: @escaping (Double) -> Void,
             onFinish: @escaping () -> Void) {
    frame = onFrame
    finish = onFinish
  }

  func surfaceEnded(at time: Double) { ends.append(time) }
  func cancel() { cancelled = true }
  func finishIfOverdue() {}
}

@MainActor
private final class Fixture {
  let samples = Samples()
  let bands = Parts([.band])
  let edges = Parts([.edge])
  let corners = Parts(ScreenCorner.allCases.map(BarPart.corner))
  lazy var keys = Keys(samples)
  var clocks: [Clock] = []
  var ordered: [Int] = []
  var lines: [String] = []
  var delayed: [(Double, DispatchWorkItem)] = []
  let settings: AppSettings
  lazy var controller: OverlayController = {
    let controller = OverlayController(
      settings: settings, displays: { [unowned self] in self.samples.screens }, sampler: samples,
      bands: bands, edges: edges, corners: corners, keys: keys,
      makeClock: { [unowned self] _ in
        let clock = Clock()
        self.clocks.append(clock)
        return clock
      },
      orderFront: { [unowned self] in self.ordered.append($0) },
      scheduleRebuild: { [unowned self] in self.delayed.append(($0, $1)) },
      testCopy: true, registryLine: { [unowned self] in self.lines.append($0) })
    keys.controller = controller
    return controller
  }()

  init() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    settings = AppSettings(defaults: defaults)
    samples.screens = [display()]
    samples.windows = [menu()]
  }

  func display(_ id: UInt32 = 1, scale: CGFloat = 2) -> BarDisplay {
    let frame = CGRect(x: CGFloat(id - 1) * 1800, y: 0, width: 1512, height: 982)
    return .init(id: id, frame: frame, visibleFrame: CGRect(x: frame.minX, y: 0, width: 1512, height: 949),
                 safeAreaTop: 32, scale: scale, notchWidth: 180, isBuiltin: id == 1)
  }

  func menu(_ id: UInt32 = 1) -> MenuBarEvidence.Window {
    .init(owner: .windowServer, layer: 24, bounds: CGRect(x: display(id).frame.minX, y: 949, width: 1512, height: 33))
  }

  func surface(_ layer: Int, alpha: Double = 1) -> MenuBarEvidence.Window {
    .init(owner: .desktop, layer: layer, bounds: display().frame, isWindowManager: true, alpha: alpha, number: 99)
  }

  func deliver(_ windows: [MenuBarEvidence.Window]?) {
    samples.now += 1
    samples.windows = windows
    controller.sample()
  }
}

@MainActor
final class OverlayCoordinatorTests: XCTestCase {
  func testARebuildAppliesOnePlanAndOrdersBandAndCornersFront() throws {
    let fixture = Fixture()
    fixture.controller.start()
    XCTAssertEqual(fixture.samples.events, ["list", "closeChanged", "active 1", "keys"])
    XCTAssertEqual(fixture.bands.plans.count, 1)
    XCTAssertEqual(fixture.edges.plans, fixture.bands.plans)
    XCTAssertEqual(fixture.corners.plans, fixture.bands.plans)
    XCTAssertEqual(fixture.keys.plans, fixture.bands.plans)
    let desktop = try XCTUnwrap(fixture.bands.plans.last?.displays[1])
    XCTAssertEqual(desktop.kind, .desktop)
    XCTAssertEqual(desktop.band.alpha, .value(1))
    XCTAssertEqual(desktop.edge.alpha, .value(1))
    XCTAssertEqual(desktop.corners.values.filter { $0.alpha == .value(1) }.count, 4)
    XCTAssertEqual(Set(fixture.ordered), [11, 13, 14, 15, 16])
    XCTAssertEqual(fixture.keys.creations.count, 1)
    let lines = fixture.lines.filter { !$0.contains("part=summary") }
    XCTAssertEqual(lines.count, 8)
    XCTAssertTrue(lines.contains { $0.contains("part=key ") && $0.contains("alpha=0 level=26 window=101") })
    let old = try XCTUnwrap(desktop.key.create)
    for _ in 0..<4 {
      fixture.controller.systemChanged(.space, uptime: fixture.samples.now)
      fixture.deliver([fixture.menu()])
    }
    XCTAssertEqual(fixture.keys.creations.count, 3)
    fixture.keys.active[1] = [101]
    fixture.keys.closed = [1]
    fixture.samples.screens = [fixture.display(scale: 1)]
    fixture.samples.events.removeAll()
    fixture.deliver([fixture.menu()])
    XCTAssertEqual(fixture.samples.events, ["list", "closeChanged", "active 1", "keys"])
    XCTAssertEqual(fixture.keys.creations.count, 4)
    XCTAssertFalse(fixture.controller.keyCommitted(old, window: 9, display: 1))
    for ids in [[104, 101, 104], [101, 104, 101]] {
      fixture.keys.active[1] = ids
      fixture.deliver([fixture.menu()])
      XCTAssertEqual(fixture.keys.plans.last?.displays[1]?.key.close, [104])
      XCTAssertEqual(fixture.keys.plans.last?.displays[1]?.key.gates, [101: .value(1)])
    }
    fixture.settings.hideNotch = false
    fixture.keys.closed = [1]
    fixture.controller.settingsChanged()
    XCTAssertFalse(try XCTUnwrap(fixture.bands.plans.last?.displays[1]).band.exists)
    fixture.settings.hideNotch = true
    fixture.controller.settingsChanged()
    XCTAssertEqual(fixture.keys.creations.count, 5)
    XCTAssertFalse(fixture.controller.keyCommitted(old, window: 10, display: 1))
  }

  func testASampleAppliesThePlanAndWritesTheRegistry() throws {
    let fixture = Fixture()
    fixture.samples.screens += [fixture.display(2), fixture.display(scale: 1)]
    fixture.samples.windows = [fixture.menu(), fixture.menu(2)]
    fixture.controller.start()
    XCTAssertTrue(fixture.lines.contains {
      $0.contains("display=1 scene=desktop part=summary") && $0.hasSuffix("blackBottom=68")
    })
    fixture.keys.active = [1: [101], 2: [102]]
    for (surfaces, kind) in [([fixture.surface(18), fixture.surface(19)], BarSceneKind.revealed),
                             ([fixture.surface(19), fixture.surface(18)], .overview)] {
      fixture.deliver([fixture.menu(), fixture.menu(2)] + surfaces)
      let display = try XCTUnwrap(fixture.bands.plans.last?.displays[1])
      XCTAssertEqual(display.kind, kind)
      XCTAssertEqual(display.band.alpha, .value(0))
      XCTAssertEqual(display.edge.alpha, .value(0))
      XCTAssertEqual(display.key.gates[101], .value(0))
      XCTAssertEqual(fixture.bands.plans.last?.displays[2]?.band.alpha, .value(1))
      XCTAssertTrue(fixture.samples.fast)
    }
    try checkDuplicateDocumentRows(in: fixture)
    fixture.samples.fullScreen = true
    let native = MenuBarEvidence.Window(owner: .application, layer: 0, bounds: fixture.display(2).visibleFrame,
                                        isFrontmostApp: true)
    fixture.deliver([fixture.menu(), fixture.menu(2), native])
    XCTAssertEqual(fixture.bands.plans.last?.displays[1]?.kind, .desktop)
    XCTAssertEqual(fixture.keys.plans.last?.displays[2]?.key.close, [102])
    fixture.samples.fullScreen = false
    fixture.deliver(nil)
    XCTAssertEqual(fixture.bands.plans.last?.displays[1]?.kind, .unknown)
    fixture.samples.screens = [fixture.display(2)]
    fixture.deliver([fixture.menu(2)])
    XCTAssertEqual(fixture.bands.plans.last?.displays[1]?.band.alpha, .hold)
    XCTAssertEqual(fixture.bands.plans.last?.displays[1]?.edge.alpha, .value(0))
    fixture.samples.screens = [fixture.display(), fixture.display(2)]
    fixture.keys.active = [1: [101], 2: [103]]
    fixture.deliver([fixture.menu(), fixture.menu(2)])
    XCTAssertEqual(fixture.keys.plans.last?.displays[1]?.key.gates[101], .value(1))
    XCTAssertEqual(fixture.keys.plans.last?.displays[2]?.key.gates[103], .value(1))
    fixture.controller.keyDidFail()
    fixture.deliver([fixture.menu(), fixture.menu(2)])
    XCTAssertFalse(fixture.samples.monitoring)
    for display in try XCTUnwrap(fixture.keys.plans.last).displays.values {
      XCTAssertFalse(display.key.exists)
      XCTAssertTrue(display.band.exists)
    }
  }

  private func row(_ owner: String, layer: Int, origin: (left: Int, top: Int),
                   size: (width: Int, height: Int), number: Int? = nil) -> [String: Any] {
    var value: [String: Any] = [
      kCGWindowOwnerPID as String: 2, kCGWindowOwnerName as String: owner,
      kCGWindowLayer as String: layer, kCGWindowAlpha as String: 1,
      kCGWindowBounds as String: ["X": origin.left, "Y": origin.top, "Width": size.width, "Height": size.height]
    ]
    if let number { value[kCGWindowNumber as String] = number }
    return value
  }

  private func checkDuplicateDocumentRows(in fixture: Fixture) throws {
    // Quartz rows include an unnumbered menu and two different bounds for one document number.
    let menu = row("Window Server", layer: 24, origin: (0, 0), size: (1512, 33))
    let reveal = row("WindowManager", layer: 18, origin: (0, 0), size: (1512, 982), number: 99)
    let home = row("Editor", layer: 0, origin: (264, 118), size: (832, 769), number: 80)
    let parked = row("Editor", layer: 0, origin: (-820, 47), size: (832, 769), number: 80)
    for duplicate in [false, true] {
      let rows = [[menu, home], [menu, parked, reveal] + (duplicate ? [home] : []), [menu, parked]]
      for list in rows {
        let windows = try XCTUnwrap(MenuBarEvidence.windows(from: list, ownPID: 1, primaryScreenHeight: 982))
        fixture.deliver(windows)
      }
      XCTAssertEqual(fixture.bands.plans.last?.displays[1]?.kind, duplicate ? .desktop : .revealed)
    }
  }

  func testASpaceChangeRebuildsAtOnceAndAScreenChangeWaits250ms() throws {
    for notificationFirst in [false, true] {
      let fixture = Fixture()
      fixture.samples.reduced = false
      fixture.controller.start()
      fixture.deliver([fixture.menu(), fixture.surface(19)])
      fixture.samples.windows = [fixture.menu()]
      if notificationFirst { fixture.controller.systemChanged(.space, uptime: fixture.samples.now) }
      let before = fixture.clocks.count
      fixture.controller.sample()
      XCTAssertEqual(fixture.clocks.count, before + (notificationFirst ? 0 : 1))
      if !notificationFirst { fixture.controller.systemChanged(.space, uptime: fixture.samples.now) }
      XCTAssertEqual(fixture.bands.plans.last?.displays[1]?.band.mask, BarMask.none)

      fixture.deliver([fixture.menu(), fixture.surface(19)])
      fixture.deliver([fixture.menu(), fixture.surface(19, alpha: 0.8)])
      let clock = try XCTUnwrap(fixture.clocks.last)
      XCTAssertNotEqual(fixture.keys.plans.last?.displays[1]?.key.mask, BarMask.none)
      clock.finish?()
      fixture.deliver([fixture.menu()])
      let signal = fixture.samples.now
      fixture.deliver([fixture.menu()])
      XCTAssertEqual(clock.ends.count, 1)
      XCTAssertEqual(try XCTUnwrap(clock.ends.first), signal, accuracy: 0.000_001)

      fixture.controller.replayEntrance()
      let preview = try XCTUnwrap(fixture.clocks.last)
      XCTAssertEqual(fixture.bands.plans.last?.displays[1]?.band.mask, .rect(.zero))
      XCTAssertTrue(fixture.lines.contains {
        $0.contains("part=band ") && $0.contains("mask=empty listed=unavailable")
      })
      let reads = fixture.samples.events.filter { $0 == "list" }.count
      fixture.bands.duringApply = {
        fixture.controller.sample()
        fixture.controller.systemChanged(.screen, uptime: fixture.samples.now)
        preview.frame?(200)
      }
      preview.frame?(100)
      XCTAssertTrue(preview.cancelled)
      XCTAssertEqual(fixture.bands.plans.last?.displays[1]?.band.mask, BarMask.none)
      XCTAssertEqual(fixture.samples.events.filter { $0 == "list" }.count, reads)
      XCTAssertEqual(fixture.delayed.count, 1)
      XCTAssertEqual(try XCTUnwrap(fixture.delayed.first?.0), 0.25, accuracy: 0.000_001)
      fixture.deliver([fixture.menu(), fixture.surface(19)])
      fixture.deliver([fixture.menu()])
      XCTAssertEqual(fixture.bands.plans.last?.displays[1]?.band.mask, BarMask.none)
      fixture.samples.screens = []
      fixture.delayed.first?.1.perform()
      XCTAssertTrue(try XCTUnwrap(fixture.bands.plans.last).displays.isEmpty)
    }
  }
}
