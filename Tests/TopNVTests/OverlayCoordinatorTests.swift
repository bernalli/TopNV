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
    let controller = OverlayController(settings: settings, displays: { [unowned self] in self.samples.screens }, sampler: samples,
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
    let f = Fixture()
    f.controller.start()
    XCTAssertEqual(f.samples.events, ["list", "closeChanged", "active 1", "keys"])
    XCTAssertEqual(f.bands.plans.count, 1)
    XCTAssertEqual(f.edges.plans, f.bands.plans)
    XCTAssertEqual(f.corners.plans, f.bands.plans)
    XCTAssertEqual(f.keys.plans, f.bands.plans)
    let desktop = try XCTUnwrap(f.bands.plans.last?.displays[1])
    XCTAssertEqual(desktop.kind, .desktop)
    XCTAssertEqual(desktop.band.alpha, .value(1))
    XCTAssertEqual(desktop.edge.alpha, .value(1))
    XCTAssertEqual(desktop.corners.values.filter { $0.alpha == .value(1) }.count, 4)
    XCTAssertEqual(Set(f.ordered), [11, 13, 14, 15, 16])
    XCTAssertEqual(f.keys.creations.count, 1)
    let lines = f.lines.filter { !$0.contains("part=summary") }
    XCTAssertEqual(lines.count, 8)
    XCTAssertTrue(lines.contains { $0.contains("part=key ") && $0.contains("alpha=0 level=26 window=101") })
    let old = try XCTUnwrap(desktop.key.create)
    for _ in 0..<4 {
      f.controller.systemChanged(.space, uptime: f.samples.now)
      f.deliver([f.menu()])
    }
    XCTAssertEqual(f.keys.creations.count, 3)
    f.keys.active[1] = [101]
    f.keys.closed = [1]
    f.samples.screens = [f.display(scale: 1)]
    f.samples.events.removeAll()
    f.deliver([f.menu()])
    XCTAssertEqual(f.samples.events, ["list", "closeChanged", "active 1", "keys"])
    XCTAssertEqual(f.keys.creations.count, 4)
    XCTAssertFalse(f.controller.keyCommitted(old, window: 9, display: 1))
    for ids in [[104, 101, 104], [101, 104, 101]] {
      f.keys.active[1] = ids
      f.deliver([f.menu()])
      XCTAssertEqual(f.keys.plans.last?.displays[1]?.key.close, [104])
      XCTAssertEqual(f.keys.plans.last?.displays[1]?.key.gates, [101: .value(1)])
    }
    f.settings.hideNotch = false
    f.keys.closed = [1]
    f.controller.settingsChanged()
    XCTAssertFalse(try XCTUnwrap(f.bands.plans.last?.displays[1]).band.exists)
    f.settings.hideNotch = true
    f.controller.settingsChanged()
    XCTAssertEqual(f.keys.creations.count, 5)
    XCTAssertFalse(f.controller.keyCommitted(old, window: 10, display: 1))
  }

  func testASampleAppliesThePlanAndWritesTheRegistry() throws {
    let f = Fixture()
    f.samples.screens += [f.display(2), f.display(scale: 1)]
    f.samples.windows = [f.menu(), f.menu(2)]
    f.controller.start()
    XCTAssertTrue(f.lines.contains { $0.contains("display=1 scene=desktop part=summary") && $0.hasSuffix("blackBottom=70") })
    f.keys.active = [1: [101], 2: [102]]
    for (surfaces, kind) in [([f.surface(18), f.surface(19)], BarSceneKind.revealed),
                             ([f.surface(19), f.surface(18)], .overview)] {
      f.deliver([f.menu(), f.menu(2)] + surfaces)
      let display = try XCTUnwrap(f.bands.plans.last?.displays[1])
      XCTAssertEqual(display.kind, kind)
      XCTAssertEqual(display.band.alpha, .value(0))
      XCTAssertEqual(display.edge.alpha, .value(0))
      XCTAssertEqual(display.key.gates[101], .value(0))
      XCTAssertEqual(f.bands.plans.last?.displays[2]?.band.alpha, .value(1))
      XCTAssertTrue(f.samples.fast)
    }
    // Quartz rows include an unnumbered menu and two different bounds for one document number.
    func row(_ owner: String, layer: Int, x: Int, y: Int, width: Int, height: Int,
             number: Int? = nil) -> [String: Any] {
      var value: [String: Any] = [kCGWindowOwnerPID as String: 2, kCGWindowOwnerName as String: owner,
        kCGWindowLayer as String: layer, kCGWindowAlpha as String: 1,
        kCGWindowBounds as String: ["X": x, "Y": y, "Width": width, "Height": height]]
      if let number { value[kCGWindowNumber as String] = number }
      return value
    }
    let menu = row("Window Server", layer: 24, x: 0, y: 0, width: 1512, height: 33)
    let reveal = row("WindowManager", layer: 18, x: 0, y: 0, width: 1512, height: 982, number: 99)
    let home = row("Editor", layer: 0, x: 264, y: 118, width: 832, height: 769, number: 80)
    let parked = row("Editor", layer: 0, x: -820, y: 47, width: 832, height: 769, number: 80)
    for duplicate in [false, true] {
      let rows = [[menu, home], [menu, parked, reveal] + (duplicate ? [home] : []), [menu, parked]]
      for list in rows {
        let windows = try XCTUnwrap(MenuBarEvidence.windows(from: list, ownPID: 1, primaryScreenHeight: 982))
        f.deliver(windows)
      }
      XCTAssertEqual(f.bands.plans.last?.displays[1]?.kind, duplicate ? .desktop : .revealed)
    }
    f.samples.fullScreen = true
    let native = MenuBarEvidence.Window(owner: .application, layer: 0, bounds: f.display(2).visibleFrame,
                                        isFrontmostApp: true)
    f.deliver([f.menu(), f.menu(2), native])
    XCTAssertEqual(f.bands.plans.last?.displays[1]?.kind, .desktop)
    XCTAssertEqual(f.keys.plans.last?.displays[2]?.key.close, [102])
    f.samples.fullScreen = false
    f.deliver(nil)
    XCTAssertEqual(f.bands.plans.last?.displays[1]?.kind, .unknown)
    f.samples.screens = [f.display(2)]
    f.deliver([f.menu(2)])
    XCTAssertEqual(f.bands.plans.last?.displays[1]?.band.alpha, .hold)
    XCTAssertEqual(f.bands.plans.last?.displays[1]?.edge.alpha, .value(0))
    f.samples.screens = [f.display(), f.display(2)]
    f.keys.active = [1: [101], 2: [103]]
    f.deliver([f.menu(), f.menu(2)])
    XCTAssertEqual(f.keys.plans.last?.displays[1]?.key.gates[101], .value(1))
    XCTAssertEqual(f.keys.plans.last?.displays[2]?.key.gates[103], .value(1))
    f.controller.keyDidFail()
    f.deliver([f.menu(), f.menu(2)])
    XCTAssertFalse(f.samples.monitoring)
    for display in try XCTUnwrap(f.keys.plans.last).displays.values {
      XCTAssertFalse(display.key.exists)
      XCTAssertTrue(display.band.exists)
    }
  }

  func testASpaceChangeRebuildsAtOnceAndAScreenChangeWaits250ms() throws {
    for notificationFirst in [false, true] {
      let f = Fixture()
      f.samples.reduced = false
      f.controller.start()
      f.deliver([f.menu(), f.surface(19)])
      f.samples.windows = [f.menu()]
      if notificationFirst { f.controller.systemChanged(.space, uptime: f.samples.now) }
      let before = f.clocks.count
      f.controller.sample()
      XCTAssertEqual(f.clocks.count, before + (notificationFirst ? 0 : 1))
      if !notificationFirst { f.controller.systemChanged(.space, uptime: f.samples.now) }
      XCTAssertEqual(f.bands.plans.last?.displays[1]?.band.mask, BarMask.none)

      f.deliver([f.menu(), f.surface(19)])
      f.deliver([f.menu(), f.surface(19, alpha: 0.8)])
      let clock = try XCTUnwrap(f.clocks.last)
      XCTAssertNotEqual(f.keys.plans.last?.displays[1]?.key.mask, BarMask.none)
      clock.finish?()
      f.deliver([f.menu()])
      let signal = f.samples.now
      f.deliver([f.menu()])
      XCTAssertEqual(clock.ends.count, 1)
      XCTAssertEqual(try XCTUnwrap(clock.ends.first), signal, accuracy: 0.000_001)

      f.controller.replayEntrance()
      let preview = try XCTUnwrap(f.clocks.last)
      XCTAssertEqual(f.bands.plans.last?.displays[1]?.band.mask, .rect(.zero))
      XCTAssertTrue(f.lines.contains { $0.contains("part=band ") && $0.contains("mask=empty listed=unavailable") })
      let reads = f.samples.events.filter { $0 == "list" }.count
      f.bands.duringApply = {
        f.controller.sample()
        f.controller.systemChanged(.screen, uptime: f.samples.now)
        preview.frame?(200)
      }
      preview.frame?(100)
      XCTAssertTrue(preview.cancelled)
      XCTAssertEqual(f.bands.plans.last?.displays[1]?.band.mask, BarMask.none)
      XCTAssertEqual(f.samples.events.filter { $0 == "list" }.count, reads)
      XCTAssertEqual(f.delayed.count, 1)
      XCTAssertEqual(try XCTUnwrap(f.delayed.first?.0), 0.25, accuracy: 0.000_001)
      f.deliver([f.menu(), f.surface(19)])
      f.deliver([f.menu()])
      XCTAssertEqual(f.bands.plans.last?.displays[1]?.band.mask, BarMask.none)
      f.samples.screens = []
      f.delayed.first?.1.perform()
      XCTAssertTrue(try XCTUnwrap(f.bands.plans.last).displays.isEmpty)
    }
  }
}
