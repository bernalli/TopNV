import AppKit
import Combine
import TopNVCore

/// Keeps one bar window per notched screen and four corner windows per selected screen in sync
/// with the screen layout and the user settings. It never reads or writes the wallpaper.
@MainActor
final class OverlayController: NSObject {
  private let settings: AppSettings
  private let animationPreview = BarAnimationPlayer()
  private var entrances: [UInt32: BarAnimationPlayer] = [:]
  private var entranceState = BandEntrance()
  private var entranceEvent = BandEntrance.Event.sample
  private var appliedHideNotch = false
  private var bandState = BandState()
  private let keyedOverlay = KeyedOverlayController()
  private let probe = BarRegistryProbe(testCopy: TestCopy.matches(Bundle.main.bundleIdentifier))
  private var latestEvidence: [UInt32: MenuBarEvidence.Result] = [:]
  private var barWindows: [UInt32: BarWindow] = [:]
  private var windows: [String: CornerWindow] = [:]
  /// Displays whose desktop is revealed: their base band and corners are transparent.
  private var revealedDisplays: Set<UInt32> = []
  /// Displays with rounded corners at the last rebuild.
  private var lastCornerDisplays: Set<UInt32> = []
  private var pendingScreenRebuild: Task<Void, Never>?
  private var settingsSubscription: AnyCancellable?

  init(settings: AppSettings) {
    self.settings = settings
    super.init()
  }

  func preview(_ variant: BarAnimation) {
    cancelEntrances()
    animationPreview.play(variant) { [weak self] in self?.previewTargets() ?? [] }
  }

  private func corners(on id: UInt32) -> [ScreenCorner: CornerWindow] {
    guard wantsCorners(on: id) else { return [:] }
    var result: [ScreenCorner: CornerWindow] = [:]
    for corner in ScreenCorner.allCases { result[corner] = windows["\(id).\(corner.rawValue)"] }
    return result
  }

  private func previewTargets() -> [PreviewBandTarget] {
    guard settings.hideNotch else { return [] }
    return NSScreen.screens.compactMap { screen in
      guard let id = screen.displayID, let bar = barWindows[id], bar.alphaValue > 0 else { return nil }
      return keyedOverlay.previewTarget(screen: screen, id: id, bar: bar, corners: corners(on: id))
    }
  }

  func start() {
    keyedOverlay.onMenuEdgeSample = { [weak self] id, frame in
      self?.barWindows[id]?.menuEdge.update(frame: frame)
    }
    keyedOverlay.onRegistrySample = { [weak self] evidence, windows in
      guard let self else { return }
      latestEvidence = evidence
      recordRegistry(on: NSScreen.screens, ownWindows: windows)
    }
    keyedOverlay.onPreviewInvalidated = { [weak self] id in
      guard let self, let bar = barWindows[id] else { return }
      animationPreview.cancel(ifShowing: bar)
    }
    keyedOverlay.onDesktopSample = { [weak self] visibility, samples, layers in
      self?.apply(visibility: visibility, samples: samples, layers: layers)
    }
    keyedOverlay.onKeyWillShow = { [weak self] id, window, backdrop in
      self?.entrances[id]?.includeKey(window, backdrop: backdrop)
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(systemDidChange(_:)),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)

    let workspaceCenter = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.activeSpaceDidChangeNotification,
      NSWorkspace.didWakeNotification,
      NSWorkspace.screensDidWakeNotification,
    ] {
      workspaceCenter.addObserver(
        self, selector: #selector(systemDidChange(_:)), name: name, object: nil)
    }

    // Delivery on the next main turn reads the stored settings.
    settingsSubscription = settings.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        MainActor.assumeIsolated {
          self?.rebuild(.settingsChanged, entrance: .settings)
        }
      }

    rebuild(.screenConfigurationChanged, entrance: .settings)
  }

  @objc private func systemDidChange(_ notification: Notification) {
    animationPreview.cancel()
    cancelEntrances()
    entranceEvent = .system
    if notification.name == NSWorkspace.activeSpaceDidChangeNotification {
      rebuild(.spaceChanged, entrance: .system)
    } else {
      // Samples during a configuration burst may contain either layout.
      pendingScreenRebuild?.cancel()
      pendingScreenRebuild = Task { @MainActor [weak self] in
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        self?.pendingScreenRebuild = nil
        self?.rebuild(.screenConfigurationChanged, entrance: .system)
      }
    }
  }

  private func cancelEntrances() {
    for player in entrances.values { player.cancel() }
    entrances.removeAll()
  }

  private func rebuild(_ event: BandState.Event, entrance: BandEntrance.Event) {
    animationPreview.cancel()
    cancelEntrances()
    appliedHideNotch = settings.hideNotch
    entranceEvent = pendingScreenRebuild == nil ? entrance : .system
    defer { entranceEvent = pendingScreenRebuild == nil ? .sample : .system }
    let screens = NSScreen.screens
    var orderAfterSampling = prepareBars(on: screens, event: event)
    let cornerDisplays = currentCornerDisplays(on: screens, event: event)

    var desiredKeys: Set<String> = []

    for screen in screens {
      guard let displayID = screen.displayID, cornerDisplays.contains(displayID) else { continue }
      let rects = ScreenGeometry.cornerRects(
        frame: screen.frame, radius: ScreenGeometry.cornerRadius,
        topInset: bandState.frames[displayID]?.height ?? 0)
      for (corner, rect) in rects {
        let key = "\(displayID).\(corner.rawValue)"
        desiredKeys.insert(key)
        let window = prepare(key: key, frame: rect) { CornerWindow(corner: corner, frame: rect) }
        window.desktopVisible = !revealedDisplays.contains(displayID)
        orderAfterSampling.append(window)
      }
    }

    updateKeyedOverlay(spaceChanged: event == .spaceChanged)
    for window in orderAfterSampling { window.orderFrontRegardless() }

    defer { recordRegistry(on: screens, ownWindows: nil) }
    // A Space switch is not a topology change for the corners either: a screen that is missing
    // from the list at that moment keeps its corners until a screen or settings event.
    guard event != .spaceChanged else { return }
    for key in windows.keys where !desiredKeys.contains(key) {
      windows[key]?.orderOut(nil)
      windows[key]?.close()
      windows[key] = nil
    }
  }

  private func recordRegistry(on screens: [NSScreen], ownWindows: [MenuBarEvidence.Window]?) {
    let snapshot = BarRegistryProbe.snapshot(screens: screens, bars: barWindows, corners: windows,
                                             keys: keyedOverlay.registryKeys(), evidence: latestEvidence)
    probe.record(snapshot, ownWindows: ownWindows)
  }

  private func prepareBars(on screens: [NSScreen], event: BandState.Event) -> [OverlayWindow] {
    let measurements = screens.compactMap { screen -> BandState.Screen? in
      guard let id = screen.displayID else { return nil }
      return BandState.Screen(
        id: id, frame: screen.frame, visibleFrame: screen.visibleFrame,
        safeAreaTop: screen.safeAreaInsets.top)
    }
    var orderAfterSampling: [OverlayWindow] = []
    for action in bandState.update(event, screens: measurements, hideNotch: settings.hideNotch) {
      switch action {
      case .show(let id, let frame):
        let window = barWindows[id] ?? BarWindow(frame: frame)
        barWindows[id] = window
        if window.frame != frame {
          window.setFrame(frame, display: false)
        }
        window.alphaValue = revealedDisplays.contains(id) ? 0 : 1
        orderAfterSampling.append(window)
      case .close(let id):
        barWindows[id]?.orderOut(nil)
        barWindows[id]?.close()
        barWindows[id] = nil
      }
    }
    return orderAfterSampling
  }

  private func updateKeyedOverlay(spaceChanged: Bool) {
    keyedOverlay.update(frames: bandState.frames, enabled: settings.hideNotch,
                        spaceChanged: spaceChanged, cornerDisplays: lastCornerDisplays)
  }

  /// A screen missing from the list during a Space switch keeps its corners in `rebuild`. It
  /// keeps their samples too, or they would no longer step aside until the next rebuild.
  private func currentCornerDisplays(on screens: [NSScreen], event: BandState.Event) -> Set<UInt32> {
    let present = Set(screens.compactMap(\.displayID))
    var result = present.filter { wantsCorners(on: $0) }
    if event == .spaceChanged { result.formUnion(lastCornerDisplays.subtracting(present)) }
    lastCornerDisplays = result
    return result
  }

  private func wantsCorners(on displayID: CGDirectDisplayID) -> Bool {
    settings.roundCorners && (settings.cornersOnAllDisplays || CGDisplayIsBuiltin(displayID) != 0)
  }

  private func apply(visibility: [UInt32: Bool], samples: [UInt32: BandEntrance.Sample],
                     layers: [UInt32: Int]) {
    let signalTime = CACurrentMediaTime()
    let hidden = Set(visibility.compactMap { $0.value ? nil : $0.key })
    let changed = hidden != revealedDisplays
    if changed { animationPreview.cancel() }
    animationPreview.finishIfOverdue()
    for player in entrances.values { player.finishIfOverdue() }
    let actions = entranceState.update(entranceEvent, enabled: appliedHideNotch, samples: samples,
                                       reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    for (id, action) in actions {
      switch action {
      case .restore: entrances.removeValue(forKey: id)?.cancel()
      case .start:
        guard let bar = barWindows[id], let screen = NSScreen.screens.first(where: { $0.displayID == id })
        else { continue }
        animationPreview.cancel(ifShowing: bar)
        let player = entrances[id] ?? BarAnimationPlayer()
        entrances[id] = player
        player.enter(PreviewBandTarget(notchWidth: screen.previewNotchWidth, bar: bar, keyed: nil,
                                       backdrops: [], corners: corners(on: id)), on: screen,
                     returnSignal: entranceEvent == .sample ? signalTime : nil, displayID: id)
        keyedOverlay.includeVisibleKeys(on: id, in: player)
      }
    }
    for (id, player) in entrances where samples[id] == .desktop && layers[id] == nil {
      player.surfaceEnded(at: signalTime)
    }
    guard changed else { return }
    revealedDisplays = hidden
    for (id, window) in barWindows {
      window.alphaValue = revealedDisplays.contains(id) ? 0 : 1
    }
    for (key, window) in windows {
      let hidden = revealedDisplays.contains { key.hasPrefix("\($0).") }
      window.desktopVisible = !hidden
    }
  }

  private func prepare(key: String, frame: CGRect, make: () -> CornerWindow) -> CornerWindow {
    let window = windows[key] ?? make()
    windows[key] = window
    if window.frame != frame {
      window.setFrame(frame, display: false)
    }
    window.contentView?.needsDisplay = true
    return window
  }
}

extension NSScreen {
  var displayID: CGDirectDisplayID? {
    deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
  }
}
