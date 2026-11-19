import AppKit
import Combine
import TopNVCore

/// Keeps one bar window per notched screen and four corner windows per selected screen in sync
/// with the screen layout and the user settings. It never reads or writes the wallpaper.
@MainActor
final class OverlayController: NSObject {
  private enum Delay {
    /// Screen configuration notifications arrive in bursts; wait for the layout to settle.
    static let system: Duration = .milliseconds(250)
    /// Short enough for a menu switch to look immediate.
    static let settings: Duration = .milliseconds(30)
  }

  private let settings: AppSettings
  private let animationPreview: BarAnimationPreview?
  private var bandState = BandState()
  private let keyedOverlay: KeyedOverlayController
  private var barWindows: [UInt32: OverlayWindow] = [:]
  private var windows: [String: OverlayWindow] = [:]
  /// Displays whose desktop is revealed: their base band and corners are transparent.
  private var revealedDisplays: Set<UInt32> = []
  /// Displays with rounded corners at the last rebuild.
  private var lastCornerDisplays: Set<UInt32> = []
  private var pendingScreenRebuild: Task<Void, Never>?
  private var pendingSettingsRebuild: Task<Void, Never>?
  private var settingsSubscription: AnyCancellable?

  /// `keyCalibration` is nil in production; a test copy passes the candidate it starts with.
  init(settings: AppSettings, keyCalibration: KeyCalibration? = nil) {
    self.settings = settings
    animationPreview = keyCalibration == nil ? nil : BarAnimationPreview()
    keyedOverlay = KeyedOverlayController(calibration: keyCalibration)
    super.init()
  }

  /// Test copies only; see `KeyedOverlayController.calibrate(_:)`.
  func calibrateKey(_ calibration: KeyCalibration) {
    animationPreview?.cancel()
    keyedOverlay.calibrate(calibration)
  }

  func preview(_ variant: BarAnimation) {
    animationPreview?.play(variant) { [weak self] in self?.previewTargets() ?? [] }
  }

  private func previewTargets() -> [PreviewBandTarget] {
    guard settings.hideNotch else { return [] }
    return NSScreen.screens.compactMap { screen in
      guard let id = screen.displayID, let bar = barWindows[id], bar.alphaValue > 0 else { return nil }
      var corners: [ScreenCorner: OverlayWindow] = [:]
      if wantsCorners(on: id) {
        for corner in ScreenCorner.allCases { corners[corner] = windows["\(id).\(corner.rawValue)"] }
      }
      return keyedOverlay.previewTarget(screen: screen, id: id, bar: bar, corners: corners)
    }
  }

  func start() {
    if animationPreview != nil {
      keyedOverlay.onPreviewInvalidated = { [weak self] displayID in
        guard let self, let bar = barWindows[displayID] else { return }
        animationPreview?.cancel(ifShowing: bar)
      }
    }
    keyedOverlay.onDesktopOverlayVisibility = { [weak self] visibility in
      self?.desktopOverlayVisibilityDidChange(visibility)
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

    // objectWillChange fires before the new value is stored; the delayed rebuild reads it after.
    settingsSubscription = settings.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        MainActor.assumeIsolated {
          self?.scheduleRebuild(.settingsChanged, after: Delay.settings)
        }
      }

    rebuild(.screenConfigurationChanged)
  }

  @objc private func systemDidChange(_ notification: Notification) {
    animationPreview?.cancel()
    if notification.name == NSWorkspace.activeSpaceDidChangeNotification {
      rebuild(.spaceChanged)
    } else {
      // Both system wake and display wake require a fresh, confirmed layout.
      scheduleRebuild(.screenConfigurationChanged, after: Delay.system)
    }
  }

  private func scheduleRebuild(_ event: BandState.Event, after delay: Duration) {
    // A settings change must not cancel a pending screen-configuration measurement.
    if event == .screenConfigurationChanged {
      pendingScreenRebuild?.cancel()
    } else {
      pendingSettingsRebuild?.cancel()
    }
    let task = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return  // Cancelled by a newer request of the same kind.
      }
      self?.rebuild(event)
    }
    if event == .screenConfigurationChanged {
      pendingScreenRebuild = task
    } else {
      pendingSettingsRebuild = task
    }
  }

  private func rebuild(_ event: BandState.Event) {
    animationPreview?.cancel()
    let screens = NSScreen.screens
    let measurements = screens.compactMap { screen -> BandState.Screen? in
      guard let id = screen.displayID else { return nil }
      return BandState.Screen(
        id: id, frame: screen.frame, visibleFrame: screen.visibleFrame,
        safeAreaTop: screen.safeAreaInsets.top)
    }
    for action in bandState.update(event, screens: measurements, hideNotch: settings.hideNotch) {
      switch action {
      case .show(let id, let frame):
        let window = barWindows[id] ?? BarWindow(frame: frame)
        barWindows[id] = window
        if window.frame != frame {
          window.setFrame(frame, display: false)
        }
        window.alphaValue = revealedDisplays.contains(id) ? 0 : 1
        window.orderFrontRegardless()
      case .close(let id):
        barWindows[id]?.orderOut(nil)
        barWindows[id]?.close()
        barWindows[id] = nil
      }
    }

    let cornerDisplays = currentCornerDisplays(on: screens, event: event)
    keyedOverlay.update(frames: bandState.frames, enabled: settings.hideNotch,
                        spaceChanged: event == .spaceChanged, cornerDisplays: cornerDisplays)

    var desiredKeys: Set<String> = []

    for screen in screens {
      guard let displayID = screen.displayID, cornerDisplays.contains(displayID) else { continue }
      let rects = ScreenGeometry.cornerRects(
        frame: screen.frame, radius: ScreenGeometry.cornerRadius,
        topInset: bandState.frames[displayID]?.height ?? 0)
      for (corner, rect) in rects {
        let key = "\(displayID).\(corner.rawValue)"
        desiredKeys.insert(key)
        show(key: key, frame: rect) { CornerWindow(corner: corner, frame: rect) }
        windows[key]?.alphaValue = revealedDisplays.contains(displayID) ? 0 : 1
      }
    }

    // A Space switch is not a topology change for the corners either: a screen that is missing
    // from the list at that moment keeps its corners until a screen or settings event.
    guard event != .spaceChanged else { return }
    for key in windows.keys where !desiredKeys.contains(key) {
      windows[key]?.orderOut(nil)
      windows[key]?.close()
      windows[key] = nil
    }
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

  /// Change opacity in place so the same windows can return on the first ordinary sample.
  private func desktopOverlayVisibilityDidChange(_ visibility: [UInt32: Bool]) {
    animationPreview?.cancel()
    revealedDisplays = Set(visibility.compactMap { $0.value ? nil : $0.key })
    for (id, window) in barWindows {
      window.alphaValue = revealedDisplays.contains(id) ? 0 : 1
    }
    for (key, window) in windows {
      let hidden = revealedDisplays.contains { key.hasPrefix("\($0).") }
      window.alphaValue = hidden ? 0 : 1
    }
  }

  private func show(key: String, frame: CGRect, make: () -> OverlayWindow) {
    let window = windows[key] ?? make()
    windows[key] = window
    if window.frame != frame {
      window.setFrame(frame, display: false)
    }
    window.contentView?.needsDisplay = true
    window.orderFrontRegardless()
  }
}

extension NSScreen {
  fileprivate var displayID: CGDirectDisplayID? {
    deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
  }
}
