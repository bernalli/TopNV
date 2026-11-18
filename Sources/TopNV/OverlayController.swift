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
  private var bandState = BandState()
  private let keyedOverlay: KeyedOverlayController
  private var barWindows: [UInt32: OverlayWindow] = [:]
  private var windows: [String: OverlayWindow] = [:]
  private var pendingScreenRebuild: Task<Void, Never>?
  private var pendingSettingsRebuild: Task<Void, Never>?
  private var settingsSubscription: AnyCancellable?

  /// `keyCalibration` is nil in production; a test copy passes the candidate it starts with.
  init(settings: AppSettings, keyCalibration: KeyCalibration? = nil) {
    self.settings = settings
    keyedOverlay = KeyedOverlayController(calibration: keyCalibration)
    super.init()
  }

  /// Test copies only; see `KeyedOverlayController.calibrate(_:)`.
  func calibrateKey(_ calibration: KeyCalibration) {
    keyedOverlay.calibrate(calibration)
  }

  func start() {
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
        window.orderFrontRegardless()
      case .close(let id):
        barWindows[id]?.orderOut(nil)
        barWindows[id]?.close()
        barWindows[id] = nil
      }
    }

    keyedOverlay.update(frames: bandState.frames, enabled: settings.hideNotch,
                        spaceChanged: event == .spaceChanged)

    var desiredKeys: Set<String> = []

    for screen in screens {
      guard let displayID = screen.displayID else { continue }

      let wantsCorners =
        settings.roundCorners
        && (settings.cornersOnAllDisplays || CGDisplayIsBuiltin(displayID) != 0)
      if wantsCorners {
        let rects = ScreenGeometry.cornerRects(
          frame: screen.frame, radius: ScreenGeometry.cornerRadius,
          topInset: bandState.frames[displayID]?.height ?? 0)
        for (corner, rect) in rects {
          let key = "\(displayID).\(corner.rawValue)"
          desiredKeys.insert(key)
          show(key: key, frame: rect) { CornerWindow(corner: corner, frame: rect) }
        }
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
