import CoreGraphics

public struct BarSettings: Equatable, Sendable {
  public let hideNotch: Bool
  public let roundCorners: Bool
  public let cornersOnAllDisplays: Bool

  public init(hideNotch: Bool, roundCorners: Bool, cornersOnAllDisplays: Bool) {
    self.hideNotch = hideNotch
    self.roundCorners = roundCorners
    self.cornersOnAllDisplays = cornersOnAllDisplays
  }
}

public struct BarSample: Sendable {
  public let displays: [BarDisplay]
  public let windows: [MenuBarEvidence.Window]?
  public let systemFullScreen: Bool
  public let appearance: [UInt32: KeyedOverlayState.Appearance]
  public let activeKeyWindows: [UInt32: [Int]]
  public let now: Double
  public let reduceMotion: Bool
  public let signalTime: Double

  public init(displays: [BarDisplay], windows: [MenuBarEvidence.Window]?, systemFullScreen: Bool,
              appearance: [UInt32: KeyedOverlayState.Appearance], activeKeyWindows: [UInt32: [Int]],
              now: Double, reduceMotion: Bool, signalTime: Double) {
    self.displays = displays
    self.windows = windows
    self.systemFullScreen = systemFullScreen
    self.appearance = appearance
    self.activeKeyWindows = activeKeyWindows
    self.now = now
    self.reduceMotion = reduceMotion
    self.signalTime = signalTime
  }
}

public struct BarEntrance: Equatable, Sendable {
  public enum Origin: Equatable, Sendable { case settings, returnSignal, preview }
  public let origin: Origin
  public var elapsedMS: Double
  public let durationMS: Double

  public init(origin: Origin, elapsedMS: Double, durationMS: Double) {
    self.origin = origin
    self.elapsedMS = elapsedMS
    self.durationMS = durationMS
  }
}

public enum BarSystemNotification: Equatable, Sendable { case space, screen }

public struct BarKeyCreation: Equatable, Sendable {
  public let instance: UInt64
  public let reservation: KeyedOverlayState.Reservation

  public init(instance: UInt64, reservation: KeyedOverlayState.Reservation) {
    self.instance = instance
    self.reservation = reservation
  }
}

public struct BarEventEffects {
  public let cancelAll: Bool
  public let closeBands: Set<UInt32>
  public let closeCorners: Set<UInt32>
}

public enum BarEntranceEffect: Equatable, Sendable {
  case start(display: UInt32, returnSignal: Double?)
  case restore(display: UInt32)
  case surfaceEnded(display: UInt32, signalTime: Double)
}

public struct BarSampleEffects {
  public fileprivate(set) var entranceEffects: [BarEntranceEffect] = []
  public fileprivate(set) var keyDecisions: [UInt32: KeyedOverlayState.Decision] = [:]
  public fileprivate(set) var traces: [String] = []
  public fileprivate(set) var wantsFastSamples = false
}

/// Reduces one delivered event at a time. Geometry is confirmed at rebuild, while samples
/// decide presentation for every display that still owns a band or corners.
public struct BarScene {
  private var bands = BandState()
  private var entranceState = BandEntrance()
  private var desktopReturns: [UInt32: DesktopReturn] = [:]
  private var latestEvidence: [UInt32: MenuBarEvidence.Result] = [:]
  private var lastKeyTrace: [UInt32: String] = [:]
  private var spaceUptime = Double.nan
  private var reduceMotion = false

  // Completion of the presentation (including a timeout) may precede the first end signal.
  private var awaitingSurfaceEnd: Set<UInt32> = []
  private(set) var keyStates: [UInt32: KeyedOverlayState] = [:]
  public private(set) var keyInstances: [UInt32: UInt64] = [:]
  public private(set) var keyDecisions: [UInt32: KeyedOverlayState.Decision] = [:]
  public private(set) var keyFailed = false
  public private(set) var appliedHideNotch = false
  public private(set) var entranceEvent = BandEntrance.Event.sample
  public private(set) var cornerDisplays: Set<UInt32> = []
  public private(set) var entrances: [UInt32: BarEntrance] = [:]
  public private(set) var kinds: [UInt32: BarSceneKind] = [:]
  public private(set) var visibility: [UInt32: Bool] = [:]
  public var bandFrames: [UInt32: CGRect] { bands.frames }
  public var needsSamples: Bool { !cornerDisplays.isEmpty || !bands.frames.isEmpty }
  public var keyedActive: Bool { appliedHideNotch && !bands.frames.isEmpty && !keyFailed }

  public init() {}

  public func evidence(display: UInt32) -> MenuBarEvidence.Result? { latestEvidence[display] }

  @discardableResult
  public mutating func handle(_ event: BandState.Event, displays: [BarDisplay], settings: BarSettings,
                              entrance: BandEntrance.Event, screenRebuildPending: Bool) -> BarEventEffects {
    cancelEntrances()
    consumeKeyDecisions()
    appliedHideNotch = settings.hideNotch
    entranceEvent = screenRebuildPending ? .system : entrance

    var present: Set<UInt32> = []
    let screens = displays.filter { present.insert($0.id).inserted }
    let measurements = screens.map {
      BandState.Screen(id: $0.id, frame: $0.frame, visibleFrame: $0.visibleFrame, safeAreaTop: $0.safeAreaTop)
    }
    let actions = bands.update(event, screens: measurements, hideNotch: settings.hideNotch)
    let closeBands = Set(actions.compactMap { action -> UInt32? in
      if case .close(let id) = action { return id }
      return nil
    })
    let previousCorners = cornerDisplays
    let rounded = screens.filter { settings.roundCorners && (settings.cornersOnAllDisplays || $0.isBuiltin) }
    cornerDisplays = Set(rounded.map(\.id))
    if event == .spaceChanged {
      cornerDisplays.formUnion(previousCorners.subtracting(present))
      if !keyFailed {
        for id in keyStates.keys { keyStates[id]?.spaceDidChange(now: spaceUptime) }
      }
    }
    for id in keyStates.keys where bands.frames[id] == nil || !appliedHideNotch {
      keyWindowsReset(display: id)
    }
    desktopReturns.removeAll()
    return BarEventEffects(cancelAll: true, closeBands: closeBands,
                           closeCorners: event == .spaceChanged ? [] : previousCorners.subtracting(cornerDisplays))
  }

  public mutating func endEvent(screenRebuildPending: Bool) {
    entranceEvent = screenRebuildPending ? .system : .sample
  }

  public mutating func systemNotification(_ kind: BarSystemNotification, uptime: Double) {
    cancelEntrances()
    entranceEvent = .system
    if kind == .space { spaceUptime = uptime }
  }

  private mutating func cancelEntrances() {
    entrances.removeAll()
    awaitingSurfaceEnd.removeAll()
  }

  @discardableResult
  public mutating func handle(_ sample: BarSample) -> BarSampleEffects {
    var effects = BarSampleEffects()
    let previousVisibility = visibility
    let displays = Dictionary(sample.displays.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let frames = displays.values.map(\.frame)
    var bandSamples: [UInt32: BandEntrance.Sample] = [:]
    latestEvidence.removeAll()
    visibility.removeAll()
    kinds.removeAll()
    reduceMotion = sample.reduceMotion
    for id in cornerDisplays.union(bands.frames.keys).sorted() {
      guard let display = displays[id] else {
        desktopReturns[id] = nil
        visibility[id] = previousVisibility[id] ?? true
        kinds[id] = .absent
        continue
      }
      let frame = display.frame
      let strip = bands.frames[id] ?? CGRect(x: frame.minX, y: frame.maxY - 1, width: frame.width, height: 1)
      let raw = MenuBarEvidence.evaluate(frame: frame, visibleFrame: display.visibleFrame, bandFrame: strip,
                                         windows: sample.windows, systemFullScreen: sample.systemFullScreen,
                                         displayFrames: frames)
      let evidence = desktopReturns[id, default: DesktopReturn()].resolve(raw, on: frame, windows: sample.windows)
      latestEvidence[id] = evidence
      visibility[id] = CornerVisibility.visible(evidence)
      kinds[id] = BarSceneKind.classify(evidence, screenPresent: true)
      if bands.frames[id] != nil { bandSamples[id] = BandEntrance.Sample(evidence) }
    }
    effects.entranceEffects = updateEntrances(bandSamples, signalTime: sample.signalTime)
    updateKeys(sample, effects: &effects)
    for (id, shown) in visibility.sorted(by: { $0.key < $1.key }) where previousVisibility[id] != shown {
      effects.traces.append("Desktop overlays, display \(id): visible=\(shown)")
    }
    effects.wantsFastSamples = latestEvidence.values.contains { $0.revealLayer != nil || $0.desktopRevealed }
    return effects
  }

  private mutating func updateEntrances(_ samples: [UInt32: BandEntrance.Sample],
                                        signalTime: Double) -> [BarEntranceEffect] {
    let actions = entranceState.update(entranceEvent, enabled: appliedHideNotch,
                                      samples: samples, reduceMotion: reduceMotion)
    var effects: [BarEntranceEffect] = []
    for (id, action) in actions.sorted(by: { $0.key < $1.key }) {
      switch action {
      case .restore:
        entrances[id] = nil
        awaitingSurfaceEnd.remove(id)
        effects.append(.restore(display: id))
      case .start:
        let returning = entranceEvent == .sample
        startEntrance(display: id, origin: returning ? .returnSignal : .settings, elapsedMS: 0)
        if returning { awaitingSurfaceEnd.insert(id) }
        effects.append(.start(display: id, returnSignal: returning ? signalTime : nil))
      }
    }
    for id in awaitingSurfaceEnd.sorted() where samples[id] == .desktop && latestEvidence[id]?.revealLayer == nil {
      effects.append(.surfaceEnded(display: id, signalTime: signalTime))
      awaitingSurfaceEnd.remove(id)
    }
    for id in entrances.keys.sorted() where entrances[id]?.origin == .preview && !permitsPreview(display: id) {
      entrances[id] = nil
      effects.append(.restore(display: id))
    }
    return effects
  }

  private mutating func updateKeys(_ sample: BarSample, effects: inout BarSampleEffects) {
    consumeKeyDecisions()
    guard keyedActive else { return }
    // Count all known key windows, including inactive Spaces, before applying this sample.
    let windowCount = keyStates.values.reduce(0) { $0 + $1.visibility.count }
    for id in bands.frames.keys.sorted() {
      guard let evidence = latestEvidence[id] else { continue }
      let active = sample.activeKeyWindows[id] ?? []
      let appearance = sample.appearance[id] ?? .unknown
      let decision = keyStates[id, default: KeyedOverlayState()].update(.init(
        activeWindowIDs: active, appearance: appearance, context: evidence.context, menuVisible: evidence.menuVisible,
        enabled: appliedHideNotch, now: sample.now, desktopRevealed: evidence.desktopRevealed,
        spaceSliding: evidence.spaceSliding, nativeFullScreen: evidence.nativeFullScreen))
      keyDecisions[id] = decision
      let gate = active.min().flatMap { keyStates[id]?.visibility[$0] }.map { "\($0)" } ?? "none"
      let trace = "appearance=\(appearance) context=\(evidence.context) "
        + "menu=\(evidence.menuVisible) revealed=\(evidence.desktopRevealed) surface=\(evidence.revealLayer ?? -1) "
        + "systemFullScreen=\(sample.systemFullScreen) nativeFullScreen=\(evidence.nativeFullScreen) "
        + "backdrop=\(evidence.fullScreenBackdrop) "
        + "sliding=\(evidence.spaceSliding) gate=\(gate) "
        + "list=\(sample.windows != nil) active=\(active.count) "
        + "windows=\(windowCount) close=\(decision.close.count) create=\(decision.create != nil)"
      if lastKeyTrace[id] != trace {
        effects.traces.append("Keyed menu bar, display \(id): \(trace)")
        lastKeyTrace[id] = trace
      }
    }
    effects.keyDecisions = keyDecisions
  }

  public mutating func consumeKeyDecisions() { keyDecisions.removeAll() }

  public mutating func keyCommitted(_ creation: BarKeyCreation, window: Int, display: UInt32) -> Bool {
    guard creation.instance == (keyInstances[display] ?? 0) else { return false }
    return keyStates[display]?.commit(creation.reservation, windowID: window) == true
  }

  public mutating func keyClosed(window: Int, display: UInt32) { keyStates[display]?.forget(window) }

  public mutating func keyWindowsReset(display: UInt32) {
    keyInstances[display, default: 0] &+= 1
    keyStates[display] = nil
    keyDecisions[display] = nil
  }

  public mutating func keyDidFail() {
    guard !keyFailed else { return }
    keyFailed = true
    for id in Set(keyStates.keys).union(bands.frames.keys) { keyWindowsReset(display: id) }
  }

  private mutating func startEntrance(display: UInt32, origin: BarEntrance.Origin, elapsedMS: Double) {
    awaitingSurfaceEnd.remove(display)
    let duration = BarAnimation.calm.durationMS(rounded: cornerDisplays.contains(display))
    entrances[display] = BarEntrance(origin: origin, elapsedMS: elapsedMS, durationMS: duration)
  }

  public mutating func advanceEntrance(display: UInt32, elapsedMS: Double) {
    guard elapsedMS.isFinite else { return }
    entrances[display]?.elapsedMS = elapsedMS
  }

  public mutating func finishEntrance(display: UInt32) { entrances[display] = nil }

  private func permitsPreview(display: UInt32) -> Bool {
    guard let evidence = latestEvidence[display] else { return false }
    return kinds[display] == .desktop && evidence.context == .desktop && evidence.menuVisible
      && !evidence.spaceSliding && !evidence.desktopRevealed
  }

  public mutating func startPreview(displays: [BarDisplay]) {
    cancelEntrances()
    guard appliedHideNotch, !reduceMotion else { return }
    for display in displays {
      let id = display.id
      if bands.frames[id] != nil && visibility[id] == true && permitsPreview(display: id) {
        startEntrance(display: id, origin: .preview, elapsedMS: -600)
      }
    }
  }
}
