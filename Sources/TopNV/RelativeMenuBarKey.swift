import BackdropRuntime
import QuartzCore
import TopNVCore
import os

/// Each keyed window follows its own bar's unfiltered mean luminance. A new window
/// starts with its ordinary filter and keeps it until the render server delivers a sample.
@MainActor final class RelativeMenuBarKey {
  static let shared = RelativeMenuBarKey()

  private final class Entry {
    let source: KOSampledBackdrop
    var background: Float?
    var applied = LuminanceKey.normal.matrix
    init(_ source: KOSampledBackdrop) { self.source = source }
  }

  private let entries = NSMapTable<CALayer, Entry>.weakToStrongObjects()
  private(set) var available: Bool
  private(set) var enabled: Bool

  init() {
    available = Self.probe()
    enabled = available
  }

  func observe(_ layer: CALayer) {
    guard available else { return }
    guard let source = KOSampledBackdrop.observe(layer, sample: { [weak self] layer, luma in
      MainActor.assumeIsolated { self?.sample(Float(luma), for: layer) }
    }) else {
      fallBack()
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
    for entry in liveEntries where !apply(entry) {
      fallBack()
      return
    }
  }

  private func sample(_ luma: Float, for layer: CALayer) {
    guard available, let entry = entries.object(forKey: layer) else { return }
    entry.background = luma
    if !apply(entry) { fallBack() }
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

  private func fallBack() {
    available = false
    enabled = false
    for entry in liveEntries where !entry.source.stopTracking() {
      Logger(subsystem: "TopNV", category: "Backdrop").error("Could not restore the ordinary key")
    }
    entries.removeAllObjects()
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
