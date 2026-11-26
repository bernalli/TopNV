import AppKit
import Combine
import TopNVCore
import os

@MainActor
final class OverlayController: NSObject {
  private static let trace = Logger(subsystem: "TopNV", category: "KeyedOverlay")
  private static let registryLog = Logger(subsystem: "TopNV", category: "BarSurface")
  private let settings: AppSettings
  private let displays: () -> [BarDisplay]
  private let sampler: BarSampling
  private let bands: BarPartExecuting
  private let edges: BarPartExecuting
  private let corners: BarPartExecuting
  private let makeClock: (UInt32) -> EntranceTiming
  private let orderFront: (Int) -> Void
  private let scheduleRebuild: (Double, DispatchWorkItem) -> Void
  private let registryLine: (String) -> Void
  private let testCopy: Bool

  var onMenuBarBackgroundChange: ((Bool) -> Void)?
  private var scene = BarScene()
  private var geometry: [UInt32: BarDisplay] = [:]
  private var clocks: [UInt32: EntranceTiming] = [:]
  private var registry: BarRegistry
  private var applied = BarRegistrySnapshot(entries: [:], displays: [:])
  private var settingsSubscription: AnyCancellable?
  private var pendingScreenRebuild: DispatchWorkItem?
  private var screenGeneration: UInt64 = 0
  private var delivering = false
  private var stopped = false
  private var keysInitialized = false
  private var pending: [() -> Void] = []

  private lazy var keys: BarKeyExecuting = {
    keysInitialized = true
    return KeyExecutor(
      keyCommitted: { [weak self] in self?.keyCommitted($0, window: $1, display: $2) ?? false },
      keyClosed: { [weak self] in self?.keyClosed(window: $0, display: $1) },
      keyDidFail: { [weak self] in self?.keyDidFail() },
      stopAppearanceMonitor: { [weak self] in self?.sampler.monitorAppearance(false) })
  }()

  convenience init(settings: AppSettings) {
    let isTestCopy = TestCopy.matches(Bundle.main.bundleIdentifier)
    self.init(settings: settings, displays: { NSScreen.screens.compactMap(BarDisplay.init(screen:)) },
              sampler: BarSampler(), bands: BandExecutor(trace: isTestCopy), edges: EdgeExecutor(),
              corners: CornerExecutor(), keys: nil, makeClock: { EntranceClock(display: $0) },
              orderFront: { NSApp.window(withWindowNumber: $0)?.orderFrontRegardless() },
              scheduleRebuild: { DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1) },
              testCopy: isTestCopy,
              registryLine: { line in OverlayController.registryLog.info("\(line, privacy: .public)") })
  }

  init(settings: AppSettings, displays: @escaping () -> [BarDisplay], sampler: BarSampling,
       bands: BarPartExecuting, edges: BarPartExecuting, corners: BarPartExecuting, keys: BarKeyExecuting?,
       makeClock: @escaping (UInt32) -> EntranceTiming, orderFront: @escaping (Int) -> Void,
       scheduleRebuild: @escaping (Double, DispatchWorkItem) -> Void, testCopy: Bool,
       registryLine: @escaping (String) -> Void) {
    self.settings = settings
    self.displays = displays
    self.sampler = sampler
    self.bands = bands
    self.edges = edges
    self.corners = corners
    self.makeClock = makeClock
    self.orderFront = orderFront
    self.scheduleRebuild = scheduleRebuild
    self.testCopy = testCopy
    self.registryLine = registryLine
    registry = BarRegistry(testCopy: testCopy)
    super.init()
    if let keys {
      self.keys = keys
      keysInitialized = true
    }
    sampler.onSample = { [weak self] in self?.sample() }
  }

  private var barSettings: BarSettings {
    .init(hideNotch: settings.hideNotch, roundCorners: settings.roundCorners,
          cornersOnAllDisplays: settings.cornersOnAllDisplays)
  }

  func start() {
    stopped = false
    sampler.onSample = { [weak self] in self?.sample() }
    NotificationCenter.default.addObserver(self, selector: #selector(systemDidChange(_:)),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
    let center = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification,
                 NSWorkspace.screensDidWakeNotification] {
      center.addObserver(self, selector: #selector(systemDidChange(_:)), name: name, object: nil)
    }
    settingsSubscription = settings.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
      MainActor.assumeIsolated { self?.settingsChanged() }
    }
    deliver { self.rebuild(.screenConfigurationChanged, entrance: .settings) }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }

  func settingsChanged() {
    deliver { self.rebuild(.settingsChanged, entrance: .settings) }
  }

  @objc private func systemDidChange(_ notification: Notification) {
    systemChanged(notification.name == NSWorkspace.activeSpaceDidChangeNotification ? .space : .screen,
                  uptime: ProcessInfo.processInfo.systemUptime)
  }

  func systemChanged(_ kind: BarSystemNotification, uptime: Double) {
    if kind == .screen { sampler.discardPending() }
    deliver { [self] in
      self.scene.systemNotification(kind, uptime: uptime)
      if kind == .space {
        self.rebuild(.spaceChanged, entrance: .system)
      } else {
        self.cancelClocks()
        self.apply(self.takePlan())
        self.pendingScreenRebuild?.cancel()
        self.screenGeneration &+= 1
        let generation = self.screenGeneration
        let work = DispatchWorkItem { [weak self] in
          self?.deliver {
            guard let self, self.screenGeneration == generation else { return }
            self.pendingScreenRebuild = nil
            self.rebuild(.screenConfigurationChanged, entrance: .system)
          }
        }
        self.pendingScreenRebuild = work
        self.scheduleRebuild(0.25, work)
      }
    }
  }

  /// Structural events and link callbacks keep delivery order through registry emission.
  /// A synchronous request for another sample is dropped, as in the original sampling loop.
  private func deliver(_ action: @escaping () -> Void) {
    guard !stopped else { return }
    guard !delivering else { pending.append(action); return }
    delivering = true
    action()
    while !stopped && !pending.isEmpty { pending.removeFirst()() }
    delivering = false
  }

  private func rebuild(_ event: BandState.Event, entrance: BandEntrance.Event) {
    sampler.discardPending()
    scene.handle(event, displays: displays(), settings: barSettings, entrance: entrance,
                 screenRebuildPending: pendingScreenRebuild != nil)
    cancelClocks()
    reconcile(rebuild: true)
    scene.endEvent(screenRebuildPending: pendingScreenRebuild != nil)
  }

  func sample() {
    guard !delivering else { return }
    deliver { self.reconcile(rebuild: false) }
  }

  private func reconcile(rebuild: Bool) {
    sampler.monitorAppearance(scene.keyedActive)
    let collected = applied
    let input = sampler.sampleNow()
    geometry = Dictionary(input.displays.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var effects = scene.handlePresentation(input) { id in
      collected.entries[.init(display: id, part: .band)]?.window.flatMap(CGWindowID.init(exactly:))
    }
    traceReturnSurfaces(input)
    if let enabled = effects.menuBarBackgroundChange { onMenuBarBackgroundChange?(enabled) }
    let closed = keys.closeChanged(frames: scene.bandFrames, enabled: scene.appliedHideNotch,
                                   scales: geometry.mapValues(\.scale))
    // handle(event:) already reset states whose frame was removed at rebuild.
    for id in closed { scene.keyWindowsReset(display: id) }
    var active: [UInt32: [Int]] = [:]
    if scene.keyedActive {
      for id in scene.bandFrames.keys.sorted() where geometry[id] != nil {
        active[id] = keys.activeWindowIDs(display: id)
      }
    }
    scene.handleKeys(input, activeWindows: active, effects: &effects)
    let plan = takePlan()
    for line in effects.traces { Self.trace.info("\(line, privacy: .public)") }
    for clock in clocks.values { clock.finishIfOverdue() }
    for effect in effects.entranceEffects {
      switch effect {
      case let .restore(display): cancelClock(display)
      case let .start(display, signal): startClock(display, returnSignal: signal)
      case let .surfaceEnded(display, time): clocks[display]?.surfaceEnded(at: time)
      }
    }
    apply(plan, rebuild: rebuild, windows: input.windows, listedAgainst: collected)
    sampler.scheduleSamples(needed: scene.needsSamples, duringReveal: effects.wantsFastSamples)
  }

  func keyCommitted(_ creation: BarKeyCreation, window: Int, display: UInt32) -> Bool {
    scene.keyCommitted(creation, window: window, display: display)
  }

  func keyClosed(window: Int, display: UInt32) {
    scene.keyClosed(window: window, display: display)
  }

  func keyDidFail() {
    let wasDelivering = delivering
    scene.keyDidFail()
    // A delayed re-commit can fail between samples. Publish its closed windows immediately.
    if !wasDelivering && !stopped { deliver { self.apply(self.takePlan()) } }
  }

  func replayEntrance() {
    guard testCopy else { return }
    deliver {
      self.scene.startPreview(displays: Array(self.geometry.values))
      let plan = self.takePlan()
      self.cancelClocks()
      for id in self.scene.entrances.keys.sorted() { self.startClock(id, returnSignal: nil) }
      self.apply(plan)
    }
  }

  private func startClock(_ id: UInt32, returnSignal: Double?) {
    cancelClock(id)
    guard let entrance = scene.entrances[id] else { return }
    let clock = makeClock(id)
    clocks[id] = clock
    clock.start(entrance, returnSignal: returnSignal, onFrame: { [weak self, weak clock] elapsed in
      guard let self, let clock else { return }
      deliver {
        guard self.clocks[id] === clock, self.scene.entrances[id] != nil else { return }
        self.scene.advanceEntrance(display: id, elapsedMS: elapsed)
        self.apply(self.takePlan())
      }
    }, onFinish: { [weak self, weak clock] in
      guard let self, let clock else { return }
      deliver {
        guard self.clocks[id] === clock, self.scene.entrances[id] != nil else { return }
        self.scene.finishEntrance(display: id)
        self.apply(self.takePlan())
      }
    })
  }

  private func cancelClock(_ id: UInt32) { clocks.removeValue(forKey: id)?.cancel() }

  private func cancelClocks() {
    for id in Array(clocks.keys) { cancelClock(id) }
  }

  private func takePlan() -> BarPlan {
    let plan = BarSurface.plan(geometry: geometry, scene: scene, entrance: scene.entrances, settings: barSettings)
    scene.consumeKeyDecisions()
    return plan
  }

  private func apply(_ plan: BarPlan, rebuild: Bool = false, windows: [MenuBarEvidence.Window]? = nil,
                     listedAgainst: BarRegistrySnapshot? = nil) {
    var entries: BarEntries = [:]
    func add(_ parts: BarEntries) { entries.merge(parts) { _, current in current } }
    applyBarPresentation {
      add(bands.apply(plan))
      add(edges.apply(plan))
      add(corners.apply(plan))
    }
    // The private backdrop attach, detach and flush must run outside the presentation transaction.
    add(keys.apply(plan))
    if rebuild {
      applyBarPresentation {
        for id in entries.keys.sorted() {
          guard plan.displays[id.display]?.geometry != nil, let number = entries[id]?.window else { continue }
          switch id.part {
          case .band, .corner: orderFront(number)
          default: break
          }
        }
      }
    }
    var displays: [UInt32: BarRegistryDisplay] = [:]
    for (id, display) in plan.displays {
      guard let geometry = display.geometry else { continue }
      let bottom = BarRegistry.blackBottom(band: entries[.init(display: id, part: .band)],
                                         edge: entries[.init(display: id, part: .edge)])
      displays[id] = .init(frame: geometry.frame, scale: geometry.scale, scene: display.kind,
                           bandEnabled: display.bandEnabled, blackBottom: bottom)
    }
    let snapshot = BarRegistrySnapshot(entries: entries, displays: displays)
    let lines = registry.record(snapshot, ownWindows: windows, listedAgainst: listedAgainst ?? applied)
    applied = snapshot
    for line in lines { registryLine(line) }
  }
}

extension OverlayController {
  func stop() {
    stopped = true
    pending.removeAll()
    NotificationCenter.default.removeObserver(
      self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
    let center = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification,
                 NSWorkspace.screensDidWakeNotification] {
      center.removeObserver(self, name: name, object: nil)
    }
    settingsSubscription?.cancel()
    settingsSubscription = nil
    pendingScreenRebuild?.cancel()
    pendingScreenRebuild = nil
    screenGeneration &+= 1
    cancelClocks()
    sampler.onSample = nil
    sampler.scheduleSamples(needed: false, duringReveal: false)
    sampler.monitorAppearance(false)
    bands.closeAll()
    edges.closeAll()
    corners.closeAll()
    if keysInitialized { keys.closeAll() }
  }

  private func traceReturnSurfaces(_ sample: BarSample) {
    guard testCopy else { return }
    for display in sample.displays {
      guard let evidence = scene.evidence(display: display.id), let surface = evidence.revealSurface else { continue }
      let time = Int(sample.signalTime * 1000)
      let line = "returnSurface display=\(display.id) atMS=\(time) layer=\(surface.layer) alpha=\(surface.alpha)"
        + " window=\(surface.number.map(String.init) ?? "none") menu=\(evidence.menuVisible)"
        + " revealed=\(evidence.desktopRevealed)"
      var detail = line
      if let windows = sample.windows, let frame = scene.bandFrames[display.id] {
        let menu = MenuBarEvidence.menuSurface(in: windows, bandFrame: frame, preferredLayer: 24)
        let docs = windows.filter {
          $0.owner == .application && $0.layer == 0 && $0.alpha > 0 && $0.bounds.intersects(display.frame)
        }.count
        detail += " menuLayer=\(menu?.layer ?? -1) menuAlpha=\(menu?.alpha ?? -1)"
          + " measuredMenu=\(evidence.menuBounds != nil) documents=\(docs)"
      }
      Self.trace.info("\(detail, privacy: .public)")
    }
  }
}
