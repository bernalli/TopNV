import AppKit
import QuartzCore
import TopNVCore
import os

@MainActor
final class KeyExecutor: BarKeyExecuting {
  typealias Schedule = @MainActor (Double, @escaping @MainActor () -> Void) -> Void
  typealias MakeWindow = @MainActor (CGRect) -> (number: Int, window: OverlayWindow)

  private struct Entry {
    let display: UInt32
    let window: OverlayWindow
    let root: CALayer
    let backdrop: CALayer
    let plate: KeyBottomPlate
    let clip: CAShapeLayer
    let scale: CGFloat
  }

  private static let logger = Logger(subsystem: "TopNV", category: "KeyedOverlay")
  private let lamp: KeyLamp
  private let runtime: KeyBackdropRuntime
  private let schedule: Schedule
  private let makeWindow: MakeWindow
  private let keyCommitted: (BarKeyCreation, Int, UInt32) -> Bool
  private let keyClosed: (Int, UInt32) -> Void
  private let keyDidFail: () -> Void
  private let stopAppearanceMonitor: () -> Void
  private var suppressedGates: [Int: CGFloat] = [:]
  private var entries: [Int: Entry] = [:]
  private(set) var failed = false

  init(runtime: KeyBackdropRuntime = PrivateBackdropRuntime(), lamp: KeyLamp? = nil,
       schedule: @escaping Schedule = { delay, run in
         DispatchQueue.main.asyncAfter(deadline: .now() + delay) { run() }
       },
       makeWindow: @escaping MakeWindow = { frame in
         let window = OverlayWindow(frame: frame, level: .init(rawValue: MenuBarEvidence.overlayLevel),
                                    isOpaque: false, behavior: OverlayBehavior.keyed)
         return (window.windowNumber, window)
       },
       keyCommitted: @escaping (BarKeyCreation, Int, UInt32) -> Bool, keyClosed: @escaping (Int, UInt32) -> Void,
       keyDidFail: @escaping () -> Void, stopAppearanceMonitor: @escaping () -> Void) {
    self.lamp = lamp ?? KeyLamp.shared
    self.runtime = runtime
    self.schedule = schedule
    self.makeWindow = makeWindow
    self.keyCommitted = keyCommitted
    self.keyClosed = keyClosed
    self.keyDidFail = keyDidFail
    self.stopAppearanceMonitor = stopAppearanceMonitor
  }

  func activeWindowIDs(display: UInt32) -> [Int] {
    entries.compactMap { id, entry in
      entry.display == display && entry.window.isOnActiveSpace ? id : nil
    }.sorted()
  }

  func closeChanged(frames: [UInt32: CGRect], enabled: Bool, scales: [UInt32: CGFloat]) -> Set<UInt32> {
    let previous = entries
    var closed: Set<UInt32> = []
    for (id, entry) in previous {
      let scaleChanged = scales[entry.display].map { $0 != entry.scale } ?? false
      if !enabled || frames[entry.display] != entry.window.frame || scaleChanged {
        closed.insert(entry.display)
        close(id)
        if failed { return Set(previous.values.map(\.display)) }
      }
    }
    return closed
  }

  @discardableResult
  func apply(_ plan: BarPlan) -> BarEntries {
    guard !failed else { return [:] }
    for (id, entry) in entries where plan.displays[entry.display]?.key.exists != true { close(id) }
    for display in plan.displays.keys.sorted() {
      guard !failed else { return [:] }
      guard let part = plan.displays[display], part.key.exists else { continue }
      do {
        try apply(part, on: display)
      } catch {
        disable(error)
        return [:]
      }
    }
    return registry(plan)
  }

  private func apply(_ part: BarDisplayPlan, on display: UInt32) throws {
    let key = part.key
    for id in key.close where entries[id]?.display == display { close(id) }
    guard !failed else { return }
    let suppress = lamp.only() && lamp.canPresent(part)
    applyBarPresentation {
      for (number, entry) in entries where entry.display == display {
        present(key, on: entry)
        applyGate(key.gates[number], on: entry.window, number: number, suppress: suppress)
      }
      applyLamp(part, on: display)
    }
    if let creation = key.create { try create(creation, on: display, plan: part) }
  }

  private func applyGate(_ gate: BarAlpha?, on window: OverlayWindow, number: Int, suppress: Bool) {
    if !suppress, suppressedGates[number] == nil {
      if let gate { window.applyAlpha(gate) }
      return
    }
    var nominal = suppressedGates[number] ?? window.alphaValue
    if case let .value(value)? = gate { nominal = value }
    if suppress {
      suppressedGates[number] = nominal
      window.applyAlpha(.value(0))
    } else {
      suppressedGates.removeValue(forKey: number)
      window.applyAlpha(.value(nominal))
    }
  }

  private func applyLamp(_ plan: BarDisplayPlan, on display: UInt32) {
    defer {
      for entry in entries.values where entry.display == display { lamp.presentPlate(entry.plate, on: display) }
    }
    guard lamp.enabled(), lamp.canPresent(plan) else {
      lamp.close(display)
      return
    }
    // Other Spaces can retain an open gate. Only the current Space can light the shared band.
    let active = activeWindowIDs(display: display).first
    guard let owner = active ?? entries.first(where: { $0.value.display == display })?.key else {
      lamp.close(display)
      return
    }
    let alpha = active.flatMap { suppressedGates[$0] ?? entries[$0]?.window.alphaValue } ?? 0
    lamp.apply(plan, display: display, owner: owner, alpha: alpha)
  }

  private func present(_ key: BarKeyPlan, on entry: Entry) {
    let bounds = entry.root.bounds
    let flipped = entry.root.isGeometryFlipped
    var extent = bounds
    if key.mask == .none {
      if entry.root.mask != nil { entry.root.mask = nil }
    } else {
      entry.clip.frame = bounds
      entry.clip.path = BarEntranceMask.path(key.mask, height: bounds.height, flipped: flipped)
      if entry.root.mask !== entry.clip { entry.root.mask = entry.clip }
      if var rect = key.backdropExtent {
        if !flipped && !rect.isEmpty { rect.origin.y = bounds.height - rect.maxY }
        extent = rect
      }
    }
    if entry.backdrop.frame != extent { entry.backdrop.frame = extent }
  }

  private func create(_ creation: BarKeyCreation, on display: UInt32, plan: BarDisplayPlan) throws {
    let key = plan.key
    guard let frame = key.frame, let geometry = key.plate, let screen = plan.geometry else { return }
    let scale = screen.scale
    let bounds = CGRect(origin: .zero, size: frame.size)
    let backdrop = try runtime.create(matrix: LuminanceKey.normal.matrix, bounds: bounds,
                                      scale: scale, display: display)
    let (id, window) = makeWindow(frame)
    let view = NSView(frame: bounds)
    applyBarPresentation {
      window.alphaValue = 0
      view.wantsLayer = true
      window.contentView = view
    }
    guard id > 0, let root = view.layer else {
      disable(BackdropFailure(reason: id > 0 ? "layer unavailable" : "overlay window has no number")) { window.close() }
      return
    }
    let entry = Entry(display: display, window: window, root: root, backdrop: backdrop,
                      plate: KeyBottomPlate(original: geometry, display: screen), clip: CAShapeLayer(), scale: scale)
    entries[id] = entry
    applyBarPresentation {
      root.contentsScale = scale
      entry.clip.contentsScale = scale
      entry.plate.install(in: root, scale: scale)
      present(key, on: entry)
    }
    try runtime.attach(root: root, backdrop: backdrop)
    guard keyCommitted(creation, id, display) else { close(id); return }
    window.orderFrontRegardless()
    window.displayIfNeeded()
    try runtime.flush()
    if lamp.enabled() { applyBarPresentation { applyLamp(plan, on: display) } }
    for delay in [0.25, 1.0] {
      schedule(delay) { [weak self, weak window] in
        guard let self, !self.failed, let window, let current = self.entries[id],
              current.window === window else { return }
        do {
          try self.runtime.recommit(current.backdrop)
        } catch {
          self.disable(error)
        }
      }
    }
  }

  private func registry(_ plan: BarPlan) -> BarEntries {
    var result: BarEntries = [:]
    for (id, entry) in entries {
      guard let display = plan.displays[entry.display] else { continue }
      let window = entry.window
      result[.init(display: entry.display, part: .key, keyWindow: id)] =
        window.registryEntry(on: display.geometry, mask: display.key.mask)
      let frame = BarPixels.windowRect(layerFrame: entry.plate.layer.frame, window: window.frame,
                                       flipped: entry.root.isGeometryFlipped)
      result[.init(display: entry.display, part: .plate, keyWindow: id)] =
        window.registryEntry(on: display.geometry, frame: frame)
    }
    return result
  }

  func closeAll() {
    for id in Array(entries.keys) { close(id) }
  }

  private func close(_ id: Int) {
    suppressedGates.removeValue(forKey: id)
    guard let entry = entries.removeValue(forKey: id) else { return }
    applyBarPresentation {
      entry.window.alphaValue = 0
      lamp.close(entry.display, owner: id)
    }
    func finishClose() {
      entry.window.close()
      keyClosed(id, entry.display)
    }
    do {
      try runtime.detach(entry.backdrop)
      finishClose()
    } catch {
      disable(error, finishing: finishClose)
    }
  }

  private func disable(_ error: Error, finishing: () -> Void = {}) {
    let firstFailure = !failed
    failed = true
    finishing()
    guard firstFailure else { return }
    Self.logger.error("Keyed menu bar disabled for this session: \(error.localizedDescription, privacy: .public)")
    stopAppearanceMonitor()
    closeAll()
    keyDidFail()
  }
}
