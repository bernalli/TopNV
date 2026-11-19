import AppKit
import BackdropRuntime
import QuartzCore
import TopNVCore
import os

/// Samples the window list for the keyed effect, base band and corners of each display.
@MainActor
final class KeyedOverlayController {
  private struct Entry {
    let window: OverlayWindow
    let backdrop: CALayer
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
  /// The last evidence logged for each display; a line is written only when it changes.
  private var traces: [UInt32: String] = [:]
  var onMenuEdgeSample: ((UInt32, CGRect?, [MenuBarEvidence.Window]?) -> Void)?
  var actualBarFrame: ((UInt32) -> CGRect?)?
  private let isTestCopy = TestCopy.matches(Bundle.main.bundleIdentifier)
  private var geometryPhases: [UInt32: String] = [:]
  private var monitor: MenuBarConditionsMonitor?
  private var timer: Timer?
  private var dock: NSRunningApplication?
  private var desktopReturns: [UInt32: DesktopReturn] = [:]
  /// Displays with a base band or corners, even if the optional keyed effect fails.
  private var sampledDisplays: Set<UInt32> = []
  private var desktopOverlayVisibility: [UInt32: Bool] = [:]
  /// Delivered before keyed gates change so a returning window already has its presentation mask.
  var onDesktopSample: (([UInt32: Bool], [UInt32: BandEntrance.Sample], [UInt32: Int]) -> Void)?
  var onKeyWillShow: ((UInt32, OverlayWindow, CALayer) -> Void)?
  var onPreviewInvalidated: ((UInt32) -> Void)?

  private var keyedActive: Bool { enabled && !frames.isEmpty && !failed }
  private var needsSamples: Bool { !sampledDisplays.isEmpty }

  func update(frames: [UInt32: CGRect], enabled: Bool, spaceChanged: Bool,
              cornerDisplays: Set<UInt32> = []) {
    self.frames = frames
    self.enabled = enabled
    self.sampledDisplays = cornerDisplays.union(frames.keys)
    if spaceChanged && !failed {
      let now = ProcessInfo.processInfo.systemUptime
      for id in states.keys { states[id]?.spaceDidChange(now: now) }
    }
    if keyedActive && monitor == nil {
      monitor = MenuBarConditionsMonitor()
      monitor?.onChange = { [weak self] in self?.reconcile() }
    }
    geometryPhases.removeAll()
    desktopReturns.removeAll()
    reconcile()
    if !keyedActive { stopMonitoring() }
  }

  private func reconcile() {
    guard !reconciling else { return }
    reconciling = true
    defer { reconciling = false }
    let screens = NSScreen.screens
    let byID = Dictionary(screens.compactMap { screen -> (UInt32, NSScreen)? in
      guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
      else { return nil }
      return (id, screen)
    }, uniquingKeysWith: { first, _ in first })
    // One copy of the window list per sample serves all overlays.
    let metadata = needsSamples ? windowMetadata(screens: screens) : nil
    let fullScreen = NSApp.currentSystemPresentationOptions.contains(.fullScreen)
    let evidence = updateDesktopOverlayVisibility(byID: byID, metadata: metadata, systemFullScreen: fullScreen)
    if !failed {
      reconcileKeyed(byID: byID, evidence: evidence, listAvailable: metadata != nil, systemFullScreen: fullScreen)
    }
    if isTestCopy { logGeometry(byID: byID, windows: metadata) }
  }

  private func reconcileKeyed(byID: [UInt32: NSScreen], evidence: [UInt32: MenuBarEvidence.Result],
                              listAvailable: Bool, systemFullScreen: Bool) {
    closeChangedWindows(byID: byID)
    guard !failed else { return }
    guard enabled, !frames.isEmpty else {
      states.removeAll()
      return
    }
    for displayID in frames.keys.sorted() {
      guard let screen = byID[displayID], let sample = evidence[displayID] else { continue }
      reconcile(displayID: displayID, screen: screen, evidence: sample, listAvailable: listAvailable,
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

  private func reconcile(displayID: UInt32, screen: NSScreen,
                         evidence: MenuBarEvidence.Result, listAvailable: Bool, systemFullScreen: Bool) {
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
    invalidatePreviewIfNeeded(on: displayID, evidence: evidence, decision: decision)
    // The gate of the active window makes the trace enough to follow a Space switch.
    let gate = active.min().flatMap { state.visibility[$0] }.map { "\($0)" } ?? "none"
    let trace = "appearance=\(appearance) context=\(evidence.context) "
      + "menu=\(evidence.menuVisible) revealed=\(evidence.desktopRevealed) surface=\(evidence.revealLayer ?? -1) "
      + "systemFullScreen=\(systemFullScreen) nativeFullScreen=\(evidence.nativeFullScreen) "
      + "backdrop=\(evidence.fullScreenBackdrop) "
      + "sliding=\(evidence.spaceSliding) gate=\(gate) "
      + "list=\(listAvailable) active=\(active.count) "
      + "windows=\(entries.count) close=\(decision.close.count) create=\(decision.create != nil)"
    if traces[displayID] != trace {
      traces[displayID] = trace
      Self.logger.info("Keyed menu bar, display \(displayID, privacy: .public): \(trace, privacy: .public)")
    }
    for id in decision.close { close(id) }
    guard !failed else { return }
    for (id, shown) in decision.gates {
      guard let entry = entries[id] else { continue }
      if shown && entry.window.alphaValue == 0 { onKeyWillShow?(displayID, entry.window, entry.backdrop) }
      entry.window.alphaValue = shown ? 1 : 0
    }
    if let reservation = decision.create, let frame = frames[displayID] {
      create(displayID: displayID, frame: frame, screen: screen, reservation: reservation)
    }
  }
}

// MARK: - Keyed window lifecycle

extension KeyedOverlayController {
  private func create(displayID: UInt32, frame: CGRect, screen: NSScreen,
                      reservation: KeyedOverlayState.Reservation) {
    guard !failed else { return }
    let scale = screen.backingScaleFactor
    let bounds = CGRect(origin: .zero, size: frame.size)
    var reason: NSString?
    guard let backdrop = Self.backdrop(LuminanceKey.normal.matrix, bounds: bounds, scale: scale, reason: &reason)
    else { disable(reason); return }

    RelativeMenuBarKey.shared.observe(backdrop)
    let window = OverlayWindow(frame: frame, level: .init(rawValue: 26), isOpaque: false,
                               behavior: OverlayBehavior.keyed)
    window.alphaValue = 0
    let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
    view.wantsLayer = true
    window.contentView = view
    guard let root = view.layer else { window.close(); disable(nil); return }
    root.contentsScale = scale
    Self.addBottomMask(to: root, size: frame.size, menuHeight: screen.frame.maxY - screen.visibleFrame.maxY,
                       scale: scale)
    // Own the resource before a private operation can fail.
    let id = window.windowNumber
    guard id > 0 else { window.close(); disable("overlay window has no number"); return }
    entries[id] = Entry(window: window, backdrop: backdrop, displayID: displayID, scale: scale)
    guard KOAttachBackdrop(root, backdrop, &reason) else { disable(reason); return }
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
          if !KORecommitBackdrop(entry.backdrop, &reason) {
            self.disable(reason)
          }
        }
      }
    }
  }

  static func addBottomMask(to root: CALayer, size: CGSize, menuHeight: CGFloat, scale: CGFloat) {
    let mask = CALayer()
    mask.frame = ScreenGeometry.keyedBottomMask(size: size, menuHeight: menuHeight,
                                               scale: scale, flipped: root.isGeometryFlipped)
    mask.name = "Bottom plate"
    mask.contentsScale = scale
    mask.backgroundColor = NSColor.black.cgColor
    mask.isOpaque = true
    mask.zPosition = 1
    root.addSublayer(mask)
  }

  private static func backdrop(_ matrix: [Float], bounds: CGRect, scale: CGFloat,
                               reason: inout NSString?) -> CALayer? {
    matrix.withUnsafeBufferPointer {
      KOCreateBackdrop($0.baseAddress!, $0.count, bounds, scale, &reason)
    }
  }

  private func close(_ id: Int) {
    guard let entry = entries.removeValue(forKey: id) else { return }
    entry.window.alphaValue = 0
    var reason: NSString?
    let detached = KODetachBackdrop(entry.backdrop, &reason)
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

  /// The appearance monitor serves only the keyed effect; the timer stops when nothing needs samples.
  private func stopMonitoring() {
    monitor?.stop()
    monitor = nil
    guard !needsSamples else { return }
    timer?.invalidate()
    timer = nil
  }
}

// MARK: - Samples shared with the base band and corners

extension KeyedOverlayController {
  /// Missing or unknown evidence keeps the overlays visible; a screen missing for a moment keeps its state.
  private func updateDesktopOverlayVisibility(byID: [UInt32: NSScreen], metadata: [MenuBarEvidence.Window]?,
                                              systemFullScreen: Bool) -> [UInt32: MenuBarEvidence.Result] {
    var results: [UInt32: MenuBarEvidence.Result] = [:]
    var visibility: [UInt32: Bool] = [:]
    var samples: [UInt32: BandEntrance.Sample] = [:]
    let displayFrames = byID.values.map(\.frame)
    for id in sampledDisplays {
      guard let screen = byID[id] else {
        onMenuEdgeSample?(id, nil, nil)
        desktopReturns[id] = nil
        visibility[id] = desktopOverlayVisibility[id] ?? true
        continue
      }
      let band = frames[id] ?? CGRect(x: screen.frame.minX, y: screen.frame.maxY - 1,
                                      width: screen.frame.width, height: 1)
      let raw = MenuBarEvidence.evaluate(frame: screen.frame, visibleFrame: screen.visibleFrame, bandFrame: band,
                                         windows: metadata, systemFullScreen: systemFullScreen,
                                         displayFrames: displayFrames)
      let evidence = desktopReturns[id, default: DesktopReturn()].resolve(raw, on: screen.frame, windows: metadata)
      results[id] = evidence
      visibility[id] = CornerVisibility.visible(evidence)
      if frames[id] != nil {
        onMenuEdgeSample?(id, evidence.menuEdgeFrame, metadata)
        samples[id] = BandEntrance.Sample(evidence)
      }
    }
    for (id, shown) in visibility where desktopOverlayVisibility[id] != shown {
      let line = "Desktop overlays, display \(id): visible=\(shown)"
      Self.logger.info("\(line, privacy: .public)")
    }
    desktopOverlayVisibility = visibility
    onDesktopSample?(visibility, samples, results.compactMapValues(\.revealLayer))
    scheduleSamples(duringReveal: results.values.contains { $0.revealLayer != nil || $0.desktopRevealed })
    return results
  }

  private func scheduleSamples(duringReveal: Bool) {
    let interval = duringReveal ? 1.0 / 30 : 0.1
    guard needsSamples, timer?.timeInterval != interval else { return }
    timer?.invalidate()
    let timer = Timer(fire: Date(timeIntervalSinceNow: interval), interval: interval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.reconcile() }
    }
    timer.tolerance = duringReveal ? 0.002 : 0.02
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  /// Copying metadata neither captures pixels nor requests Screen Recording. Window titles
  /// are deliberately never read. The first screen defines the CG/AppKit Y-axis conversion.
  private func windowMetadata(screens: [NSScreen]) -> [MenuBarEvidence.Window]? {
    guard let primary = screens.first,
          let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] else { return nil }
    if dock == nil || dock?.isTerminated == true {
      dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
    }
    return MenuBarEvidence.windows(from: list, ownPID: ProcessInfo.processInfo.processIdentifier,
                                   frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                   primaryScreenHeight: primary.frame.maxY, dockPID: dock?.processIdentifier)
  }
}

// MARK: - Test-copy geometry

extension KeyedOverlayController {
  private func logGeometry(byID: [UInt32: NSScreen], windows: [MenuBarEvidence.Window]?) {
    for id in frames.keys where geometryPhases[id] != "steady" {
      guard let screen = byID[id], let bar = actualBarFrame?(id) else { continue }
      let menu = windows.flatMap {
        MenuBarEvidence.menuSurface(in: $0, bandFrame: bar, preferredLayer: Int(CGWindowLevelForKey(.mainMenuWindow)))
      }
      let entry = entries.values.first { $0.displayID == id && $0.window.isOnActiveSpace }
      let root = entry?.window.contentView?.layer
      let plate = root?.sublayers?.first { $0.name == "Bottom plate" }
      let phase = menu == nil || entry == nil ? "incomplete" : (root?.mask == nil ? "steady" : "animating")
      guard geometryPhases[id] != phase else { continue }
      geometryPhases[id] = phase
      let geometry = OverlayGeometry(screen: screen.frame, scale: screen.backingScaleFactor)
      let line = "display=\(id) phase=\(phase) scale=\(geometry.scale) topLeftPixels "
        + "menuLayer=\(menu?.layer ?? -1) menu=\(geometry.pixels(menu?.bounds)) bar=\(geometry.pixels(bar)) "
        + "key=\(geometry.pixels(entry?.window.frame)) "
        + "plate=\(geometry.pixels(layer: plate, window: entry?.window.frame)) "
        + "backdrop=\(geometry.pixels(layer: entry?.backdrop, window: entry?.window.frame))"
      Self.logger.info("\(line, privacy: .public)")
    }
  }
}

// MARK: - Test-copy preview

extension KeyedOverlayController {
  func invalidatePreviewIfNeeded(on displayID: UInt32, evidence: MenuBarEvidence.Result,
                                 decision: KeyedOverlayState.Decision) {
    guard let onPreviewInvalidated,
          !Self.permitsPreview(evidence) || changesVisibleWindows(decision) else { return }
    onPreviewInvalidated(displayID)
  }

  private func changesVisibleWindows(_ decision: KeyedOverlayState.Decision) -> Bool {
    if !decision.close.isEmpty { return true }
    return decision.gates.contains { id, shown in
      guard let window = entries[id]?.window else { return false }
      return window.alphaValue != (shown ? 1 : 0)
    }
  }

  private static func permitsPreview(_ evidence: MenuBarEvidence.Result) -> Bool {
    evidence.context == .desktop && evidence.menuVisible && !evidence.spaceSliding && !evidence.desktopRevealed
  }

  /// Include visible windows on both Spaces until the keyed state reconciles membership.
  func includeVisibleKeys(on displayID: UInt32, in player: BarAnimationPlayer) {
    for entry in entries.values where entry.displayID == displayID && entry.window.alphaValue > 0 {
      player.includeKey(entry.window, backdrop: entry.backdrop)
    }
  }

  /// Sample only while the preview is requested. The ordinary gates continue to own window alpha.
  func previewTarget(screen: NSScreen, id: UInt32, bar: OverlayWindow,
                     corners: [ScreenCorner: CornerWindow]) -> PreviewBandTarget? {
    let evidence = MenuBarEvidence.evaluate(
      frame: screen.frame, visibleFrame: screen.visibleFrame, bandFrame: bar.frame,
      windows: windowMetadata(screens: NSScreen.screens),
      systemFullScreen: NSApp.currentSystemPresentationOptions.contains(.fullScreen))
    guard Self.permitsPreview(evidence) else { return nil }
    let entry = entries.values.first {
      $0.displayID == id && $0.window.isOnActiveSpace && $0.window.alphaValue > 0
    }
    return PreviewBandTarget(notchWidth: screen.previewNotchWidth, bar: bar, keyed: entry?.window,
                             backdrops: entry.map { [$0.backdrop] } ?? [], corners: corners)
  }
}
