import AppKit
import BackdropRuntime
import QuartzCore
import TopNVCore
import os

/// Owns only the optional keyed effect. Failure never changes the original band or corners.
@MainActor
final class KeyedOverlayController {
  private struct Entry {
    let window: OverlayWindow
    let layer: CALayer
    let displayID: UInt32
    let scale: CGFloat
  }

  private static let logger = Logger(subsystem: "TopNV", category: "KeyedOverlay")
  private var entries: [Int: Entry] = [:]
  private var states: [UInt32: KeyedOverlayState] = [:]
  private var frames: [UInt32: CGRect] = [:]
  private var enabled = false
  private var failed = false
  private var reconciling = false
  private var monitor: MenuBarConditionsMonitor?
  private var timer: Timer?

  func update(frames: [UInt32: CGRect], enabled: Bool, spaceChanged: Bool) {
    self.frames = frames
    self.enabled = enabled
    guard !failed else { return }
    if spaceChanged {
      let now = ProcessInfo.processInfo.systemUptime
      for id in states.keys { states[id]?.spaceDidChange(now: now) }
    }
    if enabled && !frames.isEmpty && monitor == nil {
      monitor = MenuBarConditionsMonitor()
      monitor?.onChange = { [weak self] in self?.reconcile() }
      let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.reconcile() }
      }
      self.timer = timer
      RunLoop.main.add(timer, forMode: .common)
    }
    reconcile()
    if !enabled || frames.isEmpty { stopMonitoring() }
  }

  private func reconcile() {
    guard !failed, !reconciling else { return }
    reconciling = true
    defer { reconciling = false }
    let screens = NSScreen.screens
    let byID = Dictionary(screens.compactMap { screen -> (UInt32, NSScreen)? in
      guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
      else { return nil }
      return (id, screen)
    }, uniquingKeysWith: { first, _ in first })
    for (id, entry) in entries {
      if !enabled || frames[entry.displayID] != entry.window.frame
        || byID[entry.displayID]?.backingScaleFactor != entry.scale {
        close(id)
      }
    }
    guard !failed else { return }
    for id in states.keys where frames[id] == nil { states[id] = nil }
    guard enabled, !frames.isEmpty else { return }
    let metadata = windowMetadata(screens: screens)
    for (displayID, frame) in frames.sorted(by: { $0.key < $1.key }) {
      guard let screen = byID[displayID] else { continue }
      let evidence = MenuBarEvidence.evaluate(frame: screen.frame, visibleFrame: screen.visibleFrame,
                                              bandFrame: frame, windows: metadata)
      var state = states[displayID] ?? KeyedOverlayState()
      let active = entries.compactMap { id, entry in
        entry.displayID == displayID && entry.window.isOnActiveSpace ? id : nil
      }
      let decision = state.update(.init(
        activeWindowIDs: active, appearance: monitor?.appearance(on: screen) ?? .unknown,
        context: evidence.context, menuVisible: evidence.menuVisible, enabled: enabled,
        now: ProcessInfo.processInfo.systemUptime))
      states[displayID] = state
      for id in decision.close { close(id) }
      guard !failed else { return }
      for (id, shown) in decision.gates {
        entries[id]?.window.alphaValue = shown ? 1 : 0
      }
      if let reservation = decision.create {
        create(displayID: displayID, frame: frame, scale: screen.backingScaleFactor,
               reservation: reservation)
      }
      guard !failed else { return }
    }
  }

  private func create(displayID: UInt32, frame: CGRect, scale: CGFloat,
                      reservation: KeyedOverlayState.Reservation) {
    let gain: Float = 5
    let row: [Float] = [-gain * 0.2126, -gain * 0.7152, -gain * 0.0722, 0, 0.5 + gain * 0.17]
    let matrix = row + row + row + [0, 0, 0, 0, 1]
    var reason: NSString?
    guard let layer = matrix.withUnsafeBufferPointer({
      KOCreateBackdrop($0.baseAddress!, $0.count, CGRect(origin: .zero, size: frame.size), scale, &reason)
    }) else { disable(reason); return }

    let window = OverlayWindow(frame: frame, level: .init(rawValue: 26), isOpaque: false,
                               behavior: OverlayBehavior.keyed)
    window.alphaValue = 0
    let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
    view.wantsLayer = true
    window.contentView = view
    guard let root = view.layer else { window.close(); disable(nil); return }
    root.contentsScale = scale
    let mask = CALayer()
    mask.frame = CGRect(x: 0, y: root.isGeometryFlipped ? frame.height - 7 : 0,
                        width: frame.width, height: 7)
    mask.contentsScale = scale
    mask.backgroundColor = NSColor.black.cgColor
    mask.isOpaque = true
    mask.zPosition = 1
    root.addSublayer(mask)
    // Own the resource before a private operation can fail.
    let id = window.windowNumber
    entries[id] = Entry(window: window, layer: layer, displayID: displayID, scale: scale)
    guard KOAttachBackdrop(root, layer, &reason) else { disable(reason); return }
    guard states[displayID]?.commit(reservation, windowID: id) == true else { close(id); return }
    window.orderFrontRegardless()
    window.displayIfNeeded()
    guard KOFlushBackdrop(&reason) else { disable(reason); return }
    // Keep the prototype's two commits, but never create/show windows from a delayed callback.
    for delay in [0.25, 1.0] {
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window] in
        MainActor.assumeIsolated {
          guard let self, !self.failed, let window,
                let entry = self.entries[id], entry.window === window else { return }
          var reason: NSString?
          if !KORecommitBackdrop(entry.layer, &reason) { self.disable(reason) }
        }
      }
    }
  }

  private func close(_ id: Int) {
    guard let entry = entries.removeValue(forKey: id) else { return }
    entry.window.alphaValue = 0
    var reason: NSString?
    let detached = KODetachBackdrop(entry.layer, &reason)
    entry.window.close()
    states[entry.displayID]?.forget(id)
    if !detached { disable(reason) }
  }

  private func disable(_ reason: NSString?) {
    guard !failed else { return }
    failed = true
    Self.logger.error("Keyed menu bar disabled for this session: \(reason as String? ?? "layer unavailable", privacy: .public)")
    stopMonitoring()
    for id in Array(entries.keys) { close(id) }
    states.removeAll()
  }

  private func stopMonitoring() {
    timer?.invalidate()
    timer = nil
    monitor?.stop()
    monitor = nil
  }

  /// Copying metadata neither captures pixels nor requests Screen Recording. Window titles
  /// are deliberately never read. The first screen defines the CG/AppKit Y-axis conversion.
  private func windowMetadata(screens: [NSScreen]) -> [MenuBarEvidence.Window]? {
    guard let main = screens.first,
          let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] else { return nil }
    var result: [MenuBarEvidence.Window] = []
    for info in list {
      guard let owner = info[kCGWindowOwnerName as String] as? String,
            let pid = info[kCGWindowOwnerPID as String] as? Int32,
            let level = info[kCGWindowLayer as String] as? Int,
            let bounds = info[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: bounds) else {
        return nil // Incomplete evidence is never permission to create.
      }
      let kind: MenuBarEvidence.Owner
      if pid == ProcessInfo.processInfo.processIdentifier { kind = .ownApp }
      else if owner == "Window Server" { kind = .windowServer }
      else if owner == "Dock" || (owner == "Finder" && level < 0) { kind = .desktop }
      else { kind = .application }
      result.append(.init(owner: kind, layer: level,
                          bounds: CGRect(x: rect.minX, y: main.frame.maxY - rect.maxY,
                                         width: rect.width, height: rect.height)))
    }
    return result
  }
}
