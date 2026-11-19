import BackdropRuntime
import QuartzCore
import TopNVCore
import os

/// Each keyed window follows its own bar's unfiltered mean luminance. A new window
/// keeps the ordinary filter unless the experiment is explicitly enabled in a test copy.
/// Test copies only: with one mean per bar a glyph lighter than 0.93 of that mean turns black,
/// and a sample taken before a window was hidden is not proven to be replaced when it returns.
@MainActor final class RelativeMenuBarKey {
  static let shared = RelativeMenuBarKey(isTestCopy: TestCopy.matches(Bundle.main.bundleIdentifier))
  private static let logger = Logger(subsystem: "TopNV", category: "RelativeKey")
  /// Samples closer than this are one line of the log.
  private static let loggedStepsPerUnit: Float = 50

  private final class Entry {
    let source: KOSampledBackdrop
    var background: Float?
    var logged: Float?
    var applied = LuminanceKey.normal.matrix
    init(_ source: KOSampledBackdrop) { self.source = source }
  }

  private let entries = NSMapTable<CALayer, Entry>.weakToStrongObjects()
  private let sink: ((String) -> Void)?
  private(set) var available: Bool
  private(set) var enabled = false

  /// - Parameter sink: receives the lines of the log in place of the system log.
  init(isTestCopy: Bool, log sink: ((String) -> Void)? = nil) {
    // Production makes none of the sampling calls, keeps the ordinary key and logs nothing.
    available = isTestCopy && Self.probe()
    self.sink = sink
    if isTestCopy { log("Relative key available=\(available)") }
  }

  func observe(_ layer: CALayer) {
    guard available else { return }
    guard let source = KOSampledBackdrop.observe(layer, sample: { [weak self] layer, luma in
      MainActor.assumeIsolated { self?.sample(Float(luma), for: layer) }
    }) else {
      fallBack("a backdrop refused the sampling setup")
      return
    }
    entries.setObject(Entry(source), forKey: layer)
  }

  private var liveEntries: [Entry] {
    entries.objectEnumerator()?.allObjects as? [Entry] ?? []
  }

  func toggle() {
    guard available else { return }
    enabled.toggle()
    log("Relative key enabled=\(enabled)")
    for entry in liveEntries where !apply(entry) {
      fallBack("a backdrop rejected its filter")
      return
    }
  }

  private func sample(_ luma: Float, for layer: CALayer) {
    guard available, let entry = entries.object(forKey: layer) else { return }
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

  private func apply(_ entry: Entry) -> Bool {
    let matrix = LuminanceKey.forBackdrop(backgroundLuma: entry.background, relativeEnabled: enabled).matrix
    guard entry.applied != matrix else { return true }
    let applied = matrix == LuminanceKey.normal.matrix
      ? entry.source.applyMatrix(nil, count: 0)
      : matrix.withUnsafeBufferPointer { entry.source.applyMatrix($0.baseAddress, count: $0.count) }
    if applied { entry.applied = matrix }
    return applied
  }

  private func fallBack(_ reason: String) {
    available = false
    enabled = false
    log("Relative key off for this session: \(reason)", failure: true)
    for entry in liveEntries where !entry.source.stopTracking() {
      log("Could not restore the ordinary key", failure: true)
    }
    entries.removeAllObjects()
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
    guard let layer, let source = KOSampledBackdrop.observe(layer, sample: { _, _ in }),
          KOAttachBackdrop(root, layer, &reason) else { return false }
    let matrix = LuminanceKey.forBackdrop(backgroundLuma: 0.8, relativeEnabled: true).matrix
    return matrix.withUnsafeBufferPointer { source.applyMatrix($0.baseAddress, count: $0.count) }
      && KORecommitBackdrop(layer, &reason) && source.applyMatrix(nil, count: 0)
      && KORecommitBackdrop(layer, &reason)
  }
}
