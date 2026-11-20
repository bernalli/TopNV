import BackdropRuntime
import QuartzCore
import TopNVCore
import os

/// Test copies can key each window against its bar's unfiltered mean luminance, or use
/// fixed endpoints while the lamp lights its display in under-key mode.
/// Test copies only: with one mean per bar a glyph lighter than 0.93 of that mean turns black,
/// and a sample taken before a window was hidden is not proven to be replaced when it returns.
@MainActor final class RelativeMenuBarKey {
  static let shared: RelativeMenuBarKey = .init(isTestCopy: TestCopy.matches(Bundle.main.bundleIdentifier),
                                                isLampLit: { KeyLamp.shared.litSince(on: $0) != nil },
                                                lampState: { KeyLamp.shared.recordState(displays: $0) })
  enum LampMode { case off, underKey, only }
  private static let logger = Logger(subsystem: "TopNV", category: "RelativeKey")
  /// Samples closer than this are one line of the log.
  private static let loggedStepsPerUnit: Float = 50

  private final class Entry {
    weak var layer: CALayer?
    var pair: KOTwoLayerBackdrop?
    let source: KOSampledBackdrop
    var background: Float?
    var logged: Float?
    var applied = LuminanceKey.normal
    var probe: BackdropProbe

    init(_ layer: CALayer, source: KOSampledBackdrop, display: UInt32) {
      self.layer = layer
      self.source = source
      probe = BackdropProbe(display: display)
    }
  }

  private let entries = NSMapTable<CALayer, Entry>.weakToStrongObjects()
  private let isTestCopy: Bool
  private(set) var lampMode: LampMode
  var lampEnabled: Bool { lampMode == .underKey }
  private(set) var lampPlate: LampPlatePreset
  private(set) var lampKey: LampKeyPreset
  private let clock: ProbeClock
  private let isLampLit: (UInt32) -> Bool
  private let lampState: (Set<UInt32>) -> Void
  private var timer: Timer?
  private let sink: ((String) -> Void)?
  private(set) var available: Bool
  private(set) var enabled = false

  /// - Parameter sink: receives the lines of the log in place of the system log.
  init(isTestCopy: Bool, clock: ProbeClock = ProbeClock(), isLampLit: @escaping (UInt32) -> Bool = { _ in true },
       lampState: @escaping (Set<UInt32>) -> Void = { _ in },
       launchPreference: () -> String? = { UserDefaults.standard.string(forKey: "LampModeAtLaunch") },
       log sink: ((String) -> Void)? = nil) {
    // Production makes none of the sampling calls, keeps the ordinary key and logs nothing.
    self.isLampLit = isLampLit
    self.clock = clock
    self.lampState = lampState
    self.isTestCopy = isTestCopy
    // A measuring run of the test copy can start with the lamp alone (set by the trial script).
    let launchOnly = isTestCopy && launchPreference() == "only"
    lampMode = isTestCopy ? (launchOnly ? .only : .underKey) : .off
    lampKey = isTestCopy ? .colorimeter : .standard
    lampPlate = isTestCopy ? .colorimeter : .standard
    available = isTestCopy && Self.probe()
    self.sink = sink
    if isTestCopy {
      log("Relative key available=\(available)")
      let mode = lampMode == .only ? "only" : "under"
      log("LampDefaults lamp=\(mode) key=\(lampKey.number) two-layer colorimeter plate=\(lampPlate.number)")
      scheduleProbes()
    }
  }

  deinit { timer?.invalidate() }

  func observe(_ layer: CALayer, display: UInt32) {
    guard isTestCopy else { return }
    var source: KOSampledBackdrop?
    if available {
      source = KOSampledBackdrop.observe(layer, sample: { [weak self] layer, luma, received in
        MainActor.assumeIsolated { self?.sample(Float(luma), for: layer, at: received) }
      })
      if source == nil {
        fallBack("a backdrop refused the sampling setup")
        // Fixed lamp keys can still use the untracked matrix path on every display.
        if lampEnabled { updateFilters() }
      }
    }
    guard let source = source ?? KOSampledBackdrop.untracked(layer) else { return }
    let entry = Entry(layer, source: source, display: display)
    entries.setObject(entry, forKey: layer)
    if !apply(entry) { fallBack("a backdrop rejected its filter") }
  }

  func resizePressed(on layer: CALayer) {
    entries.object(forKey: layer)?.pair?.pressed.frame = layer.frame
  }

  func forget(_ layer: CALayer) {
    entries.object(forKey: layer)?.pair?.remove()
    entries.removeObject(forKey: layer)
  }

  func recommitPair(on layer: CALayer) -> Bool {
    guard let pair = entries.object(forKey: layer)?.pair else { return false }
    var reason: NSString?
    if pair.recommit(&reason) { return true }
    useMeasuringKey(reason)
    return false
  }

  private func useMeasuringKey(_ reason: NSString?) {
    log("TwoLayer unavailable reason=\(reason as String? ?? "unknown")", failure: true)
    selectLampKey(.measuring)
  }

  private var liveEntries: [Entry] {
    entries.objectEnumerator()?.allObjects as? [Entry] ?? []
  }

  func toggle() {
    guard available else { return }
    enabled.toggle()
    log("Relative key enabled=\(enabled)")
    updateFilters()
    scheduleProbes()
  }

  func toggleLamp(present: () -> Void = {}) { setLamp(.underKey, present: present) }
  func toggleLampOnly(present: () -> Void = {}) { setLamp(.only, present: present) }

  private func setLamp(_ mode: LampMode, present: () -> Void) {
    guard isTestCopy else { return }
    lampMode = lampMode == mode ? .off : mode
    updateFilters()
    present()
    scheduleProbes()
  }

  func selectLampKey(_ preset: LampKeyPreset) {
    guard isTestCopy, preset.command != lampKey.command else { return }
    lampKey = preset
    if lampEnabled { updateFilters() }
  }

  func selectLampPlate(_ preset: LampPlatePreset, present: () -> Void) {
    guard isTestCopy, preset.command != lampPlate.command else { return }
    lampPlate = preset
    if lampEnabled { present() }
  }

  func lampChanged(on display: UInt32) {
    if lampEnabled { updateFilters(on: display) }
  }

  private func updateFilters(on display: UInt32? = nil) {
    for entry in liveEntries where display == nil || display == entry.probe.display {
      guard !apply(entry) else { continue }
      fallBack("a backdrop rejected its filter")
      return
    }
  }

  private func scheduleProbes() {
    guard isTestCopy, enabled || lampMode != .off else {
      timer?.invalidate()
      timer = nil
      return
    }
    guard timer == nil else { return }
    for entry in liveEntries { beginProbe(entry) }
    timer = clock.schedule(BackdropProbe.interval) { [weak self] in self?.tick() }
  }

  private func beginProbe(_ entry: Entry) {
    let start = clock.now()
    entry.probe.begin(at: start, forced: entry.source.forceSample())
  }

  private func tick() {
    let entries = liveEntries
    let time = clock.now()
    lampState(Set(entries.map { $0.probe.display }))
    for entry in entries {
      log(entry.probe.line(at: time, key: entry.pair == nil ? entry.applied : lampKey.key, fixed: usesLampKey(entry)))
      beginProbe(entry)
    }
  }

  func sample(_ luma: Float, for layer: CALayer, at time: TimeInterval) {
    guard available, let entry = entries.object(forKey: layer) else { return }
    if let previous = entry.probe.lastCallback, time < previous { return }
    entry.probe.receive(luma, at: time)
    entry.background = luma
    // A line per visible change shows the scale and the cadence of the samples in a test log,
    // with the switch off too: the points are those of the relative key for this sample.
    let step = luma.isFinite ? (luma * Self.loggedStepsPerUnit).rounded() / Self.loggedStepsPerUnit : -1
    if entry.logged != step {
      entry.logged = step
      let key = LuminanceKey.forBackdrop(backgroundLuma: luma, relativeEnabled: true)
      let numbers = [luma, key.whitePoint, key.blackPoint].map { String(format: "%.3f", $0) }
      let width = String(format: "%.0f", Double(layer.bounds.width))
      log("Sample \(numbers[0]) over \(width) pt, enabled=\(enabled), "
            + "relative key white to \(numbers[1]), black from \(numbers[2])")
    }
    if !apply(entry) { fallBack("a backdrop rejected its filter") }
  }

  private func usesLampKey(_ entry: Entry) -> Bool {
    lampEnabled && isLampLit(entry.probe.display)
  }

  private func apply(_ entry: Entry) -> Bool {
    let fixed = usesLampKey(entry)
    if fixed && lampKey.command == .lampKey6 {
      guard entry.pair == nil, let layer = entry.layer else { return true }
      var reason: NSString?
      let controls = ColorimeterKey.curve.values.map { NSNumber(value: $0) }
      entry.pair = KOInstallTwoLayer(layer, lampKey.key.matrix, controls, ColorimeterKey.threshold.matrix,
                                     ColorimeterKey.pressedLevel, &reason)
      guard entry.pair != nil else {
        useMeasuringKey(reason)
        return true
      }
      // remove() restores the filters that preceded this pair.
      log("LampKey display=\(entry.probe.display) voce=6 two-layer colorimeter")
      return true
    }
    entry.pair?.remove()
    entry.pair = nil
    let key = fixed ? lampKey.key
      : LuminanceKey.forBackdrop(backgroundLuma: entry.background, relativeEnabled: enabled)
    let matrix = key.matrix
    guard entry.applied.matrix != matrix else { return true }
    let applied = matrix == LuminanceKey.normal.matrix
      ? entry.source.applyMatrix(nil, count: 0)
      : matrix.withUnsafeBufferPointer { entry.source.applyMatrix($0.baseAddress, count: $0.count) }
    guard applied else { return false }
    entry.applied = key
    if fixed {
      log("LampKey display=\(entry.probe.display) voce=\(lampKey.number) "
          + "black=\(lampKey.blackText) white=\(lampKey.whiteText)")
    }
    return true
  }

  private func fallBack(_ reason: String) {
    available = false
    enabled = false
    log("Relative key off for this session: \(reason)", failure: true)
    for entry in liveEntries {
      entry.pair?.remove()
      entry.pair = nil
      if entry.source.stopTracking() {
        entry.applied = .normal
      } else {
        log("Could not restore the ordinary key", failure: true)
      }
    }
    scheduleProbes()
  }

  private func log(_ line: String, failure: Bool = false) {
    if let sink {
      sink(line)
    } else if failure {
      Self.logger.error("\(line, privacy: .public)")
    } else {
      Self.logger.info("\(line, privacy: .public)")
    }
  }

  private static func probe() -> Bool {
    var reason: NSString?
    let normal = LuminanceKey.normal.matrix
    let bounds = CGRect(x: 0, y: 0, width: 96, height: 28)
    let layer = normal.withUnsafeBufferPointer {
      KOCreateBackdrop($0.baseAddress!, $0.count, bounds, 1, &reason)
    }
    let root = CALayer()
    root.bounds = bounds
    guard let layer, let source = KOSampledBackdrop.observe(layer, sample: { _, _, _ in }),
          KOAttachBackdrop(root, layer, &reason) else { return false }
    let matrix = LuminanceKey.forBackdrop(backgroundLuma: 0.8, relativeEnabled: true).matrix
    return matrix.withUnsafeBufferPointer { source.applyMatrix($0.baseAddress, count: $0.count) }
      && KORecommitBackdrop(layer, &reason) && source.applyMatrix(nil, count: 0)
      && KORecommitBackdrop(layer, &reason)
  }
}
