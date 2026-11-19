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
    /// Backdrop of the menu bar: black from Y 0.3767, white up to Y 0.0433, calibrated by eye.
    /// A test copy uses its `KeyCalibration`.
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
  /// Test copies only: the chosen normal key. Nil in production, for the whole session.
  private var calibration: KeyCalibration?
  private var calibrationNeedsRebuild = false

  init(calibration: KeyCalibration? = nil) {
    self.calibration = calibration
  }

  private var normalMatrix: [Float] { KeyCalibration.normalMatrix(calibration) }
  private var normalCurve: KeyCurve? { KeyCalibration.normalCurve(calibration) }

  /// Test copies only: replaces the normal key. The windows are closed and created again, as
  /// after a change of geometry, so no live backdrop is changed. Without a calibration at
  /// launch, as in production, it does nothing.
  func calibrate(_ calibration: KeyCalibration) {
    guard self.calibration != nil, self.calibration != calibration else { return }
    self.calibration = calibration
    let line = "Key calibration: gain=\(calibration.gain) cutoff=\(calibration.cutoff) "
      + "curve=\(calibration.curve.map { "\($0.values)" } ?? "none")"
    Self.logger.info("\(line, privacy: .public)")
    guard !failed else { return }
    calibrationNeedsRebuild = true
    reconcile()
  }

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
    if calibrationNeedsRebuild, !rebuildForCalibration() { return }

    let screens = NSScreen.screens
    let byID = Dictionary(screens.compactMap { screen -> (UInt32, NSScreen)? in
      guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
      else { return nil }
      return (id, screen)
    }, uniquingKeysWith: { first, _ in first })
    closeChangedWindows(byID: byID)
    guard !failed else { return }
    guard enabled, !frames.isEmpty else {
      states.removeAll()
      return
    }
    let metadata = windowMetadata(screens: screens)
    let systemFullScreen = NSApp.currentSystemPresentationOptions.contains(.fullScreen)
    for (displayID, frame) in frames.sorted(by: { $0.key < $1.key }) {
      guard let screen = byID[displayID] else { continue }
      reconcile(displayID: displayID, frame: frame, screen: screen, metadata: metadata,
                systemFullScreen: systemFullScreen)
      guard !failed else { return }
    }
  }

  private func closeChangedWindows(byID: [UInt32: NSScreen]) {
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
  }

  private func reconcile(displayID: UInt32, frame: CGRect, screen: NSScreen,
                         metadata: [MenuBarEvidence.Window]?, systemFullScreen: Bool) {
    let evidence = MenuBarEvidence.evaluate(frame: screen.frame, visibleFrame: screen.visibleFrame,
                                            bandFrame: frame, windows: metadata, systemFullScreen: systemFullScreen)
    var state = states[displayID] ?? KeyedOverlayState()
    let active = entries.compactMap { id, entry in
      entry.displayID == displayID && entry.window.isOnActiveSpace ? id : nil
    }
    let appearance = monitor?.appearance(on: screen) ?? .unknown
    let decision = state.update(.init(
      activeWindowIDs: active, appearance: appearance,
      context: evidence.context, menuVisible: evidence.menuVisible, enabled: enabled,
      now: ProcessInfo.processInfo.systemUptime, desktopRevealed: evidence.desktopRevealed,
      spaceSliding: evidence.spaceSliding, nativeFullScreen: evidence.nativeFullScreen))
    states[displayID] = state
    // The gate of the active window makes the trace enough to follow a Space switch.
    let gate = active.min().flatMap { state.visibility[$0] }.map { "\($0)" } ?? "none"
    let trace = "appearance=\(appearance) context=\(evidence.context) "
      + "menu=\(evidence.menuVisible) revealed=\(evidence.desktopRevealed) "
      + "systemFullScreen=\(systemFullScreen) nativeFullScreen=\(evidence.nativeFullScreen) "
      + "backdrop=\(evidence.fullScreenBackdrop) "
      + "sliding=\(evidence.spaceSliding) gate=\(gate) "
      + "list=\(metadata != nil) active=\(active.count) "
      + "windows=\(entries.count) close=\(decision.close.count) create=\(decision.create != nil)"
    if traces[displayID] != trace {
      traces[displayID] = trace
      Self.logger.info("Keyed menu bar, display \(displayID, privacy: .public): \(trace, privacy: .public)")
    }
    for id in decision.close { close(id) }
    guard !failed else { return }
    if let change = decision.keyChange {
      show(change.key, on: change.windowID)
    }
    guard !failed else { return }
    for (id, shown) in decision.gates {
      entries[id]?.window.alphaValue = shown ? 1 : 0
    }
    if let reservation = decision.create {
      let key = LuminanceKey.choose(desktopRevealed: evidence.desktopRevealed)
      create(displayID: displayID, frame: frame, screen: screen, key: key, reservation: reservation)
    }
  }
}

// MARK: - Keyed window lifecycle

extension KeyedOverlayController {
  /// Closes every keyed window for a new calibration. False when closing disabled the effect.
  private func rebuildForCalibration() -> Bool {
    calibrationNeedsRebuild = false
    for id in Array(entries.keys) { close(id) }
    guard !failed else { return false }
    for id in states.keys { states[id]?.resetForWindowReplacement() }
    return true
  }

  private func create(displayID: UInt32, frame: CGRect, screen: NSScreen, key: LuminanceKey,
                      reservation: KeyedOverlayState.Reservation) {
    guard !failed else { return }
    let scale = screen.backingScaleFactor
    let bounds = CGRect(origin: .zero, size: frame.size)
    var reason: NSString?
    guard let normal = Self.backdrop(normalMatrix, curve: normalCurve, bounds: bounds, scale: scale,
                                     reason: &reason),
          let revealed = Self.backdrop(Key.revealed.matrix, curve: Key.revealed.curve, bounds: bounds,
                                       scale: scale, reason: &reason)
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

  private static func backdrop(_ matrix: [Float], curve: KeyCurve?, bounds: CGRect, scale: CGFloat,
                               reason: inout NSString?) -> CALayer? {
    let controls = curve?.values ?? []
    return matrix.withUnsafeBufferPointer { matrix in
      controls.withUnsafeBufferPointer { controls in
        KOCreateBackdrop(matrix.baseAddress!, matrix.count, controls.isEmpty ? nil : controls.baseAddress,
                         controls.count, bounds, scale, &reason)
      }
    }
  }

  /// Switches only the window whose active Space has settled.
  private func show(_ key: LuminanceKey, on id: Int) {
    guard let entry = entries[id], entry.key != key else { return }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    entry.normal.isHidden = key != Key.normal
    entry.revealed.isHidden = key != Key.revealed
    CATransaction.commit()
    var reason: NSString?
    guard KOFlushBackdrop(&reason) else { disable(reason); return }
    entries[id]?.key = key
  }

  private func close(_ id: Int) {
    guard let entry = entries.removeValue(forKey: id) else { return }
    entry.window.alphaValue = 0
    var normalReason: NSString?
    var revealedReason: NSString?
    let normalDetached = KODetachBackdrop(entry.normal, &normalReason)
    let revealedDetached = KODetachBackdrop(entry.revealed, &revealedReason)
    entry.window.close()
    states[entry.displayID]?.forget(id)
    if !normalDetached || !revealedDetached { disable(normalReason ?? revealedReason) }
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
}

// MARK: - Window list

extension KeyedOverlayController {
  /// Copying metadata neither captures pixels nor requests Screen Recording. Window titles
  /// are deliberately never read. The first screen defines the CG/AppKit Y-axis conversion.
  private func windowMetadata(screens: [NSScreen]) -> [MenuBarEvidence.Window]? {
    guard let primary = screens.first,
          let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] else { return nil }
    return MenuBarEvidence.windows(from: list, ownPID: ProcessInfo.processInfo.processIdentifier,
                                   frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                   primaryScreenHeight: primary.frame.maxY)
  }
}
