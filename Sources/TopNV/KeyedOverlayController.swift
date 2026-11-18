import AppKit
import BackdropRuntime
import QuartzCore
import TopNVCore
import os

/// Owns only the optional keyed effect. Failure never changes the original band or corners.
@MainActor
final class KeyedOverlayController {
  /// Both backdrops stay attached; only the one of the current key is visible.
  private struct Entry {
    let window: OverlayWindow
    let normal: CALayer
    let revealed: CALayer
    let displayID: UInt32
    let scale: CGFloat
    var key: LuminanceKey
  }

  /// No single linear key fits both backdrops macOS draws under the menu bar (`LuminanceKey`).
  private enum Key {
    /// Light backdrop of the menu bar: black from Y 0.7325, white up to Y 0.1075, so the
    /// antialiasing and the grey parts of the icons stay.
    static let normal = LuminanceKey.normal
    /// Darker backdrop while the desktop is revealed (Y about 0.32): black from Y 0.2833.
    static let revealed = LuminanceKey.revealed
    /// Black points over the bottom of the menu bar, where its background is below the key.
    static let maskHeight: CGFloat = 7
  }

  private static let logger = Logger(subsystem: "TopNV", category: "KeyedOverlay")
  private var entries: [Int: Entry] = [:]
  private var states: [UInt32: KeyedOverlayState] = [:]
  private var frames: [UInt32: CGRect] = [:]
  private var enabled = false
  private var failed = false
  private var reconciling = false
  /// The last evidence logged for each display; a line is written only when it changes.
  private var traces: [UInt32: String] = [:]
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
      timer.tolerance = 0.02
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
    var closedHere: Set<UInt32> = []
    for (id, entry) in entries {
      // A screen missing from the list for a moment is not a new geometry: the band stays too.
      let scaleChanged = byID[entry.displayID].map { $0.backingScaleFactor != entry.scale } ?? false
      if !enabled || frames[entry.displayID] != entry.window.frame || scaleChanged {
        closedHere.insert(entry.displayID)
        close(id)
      }
    }
    guard !failed else { return }
    // A window closed here is not a failed creation: its display starts again with a full
    // budget. Without this the fourth switch-on of the option creates nothing until relaunch.
    for id in closedHere { states[id] = nil }
    for id in states.keys where frames[id] == nil { states[id] = nil }
    guard enabled, !frames.isEmpty else {
      states.removeAll()
      return
    }
    let metadata = windowMetadata(screens: screens)
    for (displayID, frame) in frames.sorted(by: { $0.key < $1.key }) {
      guard let screen = byID[displayID] else { continue }
      let evidence = MenuBarEvidence.evaluate(frame: screen.frame, visibleFrame: screen.visibleFrame,
                                              bandFrame: frame, windows: metadata)
      var state = states[displayID] ?? KeyedOverlayState()
      let active = entries.compactMap { id, entry in
        entry.displayID == displayID && entry.window.isOnActiveSpace ? id : nil
      }
      let appearance = monitor?.appearance(on: screen) ?? .unknown
      let decision = state.update(.init(
        activeWindowIDs: active, appearance: appearance,
        context: evidence.context, menuVisible: evidence.menuVisible, enabled: enabled,
        now: ProcessInfo.processInfo.systemUptime))
      states[displayID] = state
      let trace = "appearance=\(appearance) context=\(evidence.context) "
        + "menu=\(evidence.menuVisible) revealed=\(evidence.desktopRevealed) "
        + "list=\(metadata != nil) active=\(active.count) "
        + "windows=\(entries.count) create=\(decision.create != nil)"
      if traces[displayID] != trace {
        traces[displayID] = trace
        Self.logger.info("Keyed menu bar, display \(displayID, privacy: .public): \(trace, privacy: .public)")
      }
      for id in decision.close { close(id) }
      guard !failed else { return }
      for (id, shown) in decision.gates {
        entries[id]?.window.alphaValue = shown ? 1 : 0
      }
      let key = LuminanceKey.choose(desktopRevealed: evidence.desktopRevealed)
      show(key, on: displayID)
      if let reservation = decision.create {
        create(displayID: displayID, frame: frame, screen: screen, key: key, reservation: reservation)
      }
      guard !failed else { return }
    }
  }

  private func create(displayID: UInt32, frame: CGRect, screen: NSScreen, key: LuminanceKey,
                      reservation: KeyedOverlayState.Reservation) {
    guard !failed else { return }
    let scale = screen.backingScaleFactor
    let bounds = CGRect(origin: .zero, size: frame.size)
    var reason: NSString?
    guard let normal = Self.backdrop(Key.normal, bounds: bounds, scale: scale, reason: &reason),
          let revealed = Self.backdrop(Key.revealed, bounds: bounds, scale: scale, reason: &reason)
    else { disable(reason); return }
    normal.isHidden = key != Key.normal
    revealed.isHidden = key != Key.revealed

    let window = OverlayWindow(frame: frame, level: .init(rawValue: 26), isOpaque: false,
                               behavior: OverlayBehavior.keyed)
    window.alphaValue = 0
    let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
    view.wantsLayer = true
    window.contentView = view
    guard let root = view.layer else { window.close(); disable(nil); return }
    root.contentsScale = scale
    // The band can be a point taller than the menu bar: the mask is measured from the bar.
    let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
    let below = menuBarHeight > 0 ? min(max(frame.height - menuBarHeight, 0), 1) : 0
    let maskHeight = Key.maskHeight + below
    let mask = CALayer()
    mask.frame = CGRect(x: 0, y: root.isGeometryFlipped ? frame.height - maskHeight : 0,
                        width: frame.width, height: maskHeight)
    mask.contentsScale = scale
    mask.backgroundColor = NSColor.black.cgColor
    mask.isOpaque = true
    mask.zPosition = 1
    root.addSublayer(mask)
    // Own the resource before a private operation can fail.
    let id = window.windowNumber
    guard id > 0 else { window.close(); disable("overlay window has no number"); return }
    entries[id] = Entry(window: window, normal: normal, revealed: revealed, displayID: displayID,
                        scale: scale, key: key)
    guard KOAttachBackdrop(root, normal, &reason), KOAttachBackdrop(root, revealed, &reason)
    else { disable(reason); return }
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
          if !KORecommitBackdrop(entry.normal, &reason) || !KORecommitBackdrop(entry.revealed, &reason) {
            self.disable(reason)
          }
        }
      }
    }
  }

  private static func backdrop(_ key: LuminanceKey, bounds: CGRect, scale: CGFloat,
                               reason: inout NSString?) -> CALayer? {
    key.matrix.withUnsafeBufferPointer {
      KOCreateBackdrop($0.baseAddress!, $0.count, bounds, scale, &reason)
    }
  }

  /// Switches the visible backdrop of the display's windows without recreating them. Implicit
  /// animations are off: a fading switch shows both keys at once.
  private func show(_ key: LuminanceKey, on displayID: UInt32) {
    let changed = entries.filter { $0.value.displayID == displayID && $0.value.key != key }
    guard !changed.isEmpty else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for (id, entry) in changed {
      entry.normal.isHidden = key != Key.normal
      entry.revealed.isHidden = key != Key.revealed
      entries[id]?.key = key
    }
    CATransaction.commit()
    var reason: NSString?
    if !KOFlushBackdrop(&reason) { disable(reason) }
  }

  private func close(_ id: Int) {
    guard let entry = entries.removeValue(forKey: id) else { return }
    entry.window.alphaValue = 0
    var reason: NSString?
    let detached = KODetachBackdrop(entry.normal, &reason) && KODetachBackdrop(entry.revealed, &reason)
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
    guard let primary = screens.first,
          let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] else { return nil }
    return MenuBarEvidence.windows(from: list, ownPID: ProcessInfo.processInfo.processIdentifier,
                                   primaryScreenHeight: primary.frame.maxY)
  }
}
