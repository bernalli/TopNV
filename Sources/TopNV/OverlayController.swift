import AppKit
import Combine
import TopNVCore

/// Keeps one bar window per notched screen and four corner windows per selected screen in sync
/// with the screen layout and the user settings. It never reads or writes the wallpaper.
@MainActor
final class OverlayController: NSObject {
  private enum Delay {
    /// Screen and Space notifications arrive in bursts; wait for the layout to settle.
    static let system: Duration = .milliseconds(250)
    /// Short enough to keep the radius slider live.
    static let settings: Duration = .milliseconds(30)
  }

  private let settings: AppSettings
  private var windows: [String: OverlayWindow] = [:]
  private var pendingRebuild: Task<Void, Never>?
  private var settingsSubscription: AnyCancellable?

  init(settings: AppSettings) {
    self.settings = settings
    super.init()
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
          self?.scheduleRebuild(after: Delay.settings)
        }
      }

    rebuild()
  }

  @objc private func systemDidChange(_ notification: Notification) {
    scheduleRebuild(after: Delay.system)
  }

  private func scheduleRebuild(after delay: Duration) {
    pendingRebuild?.cancel()
    pendingRebuild = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return  // Cancelled by a newer request.
      }
      self?.rebuild()
    }
  }

  /// Reconciles the existing windows with the desired set: reuses windows whose key still
  /// exists (so the bar does not flicker on Space changes) and closes the rest.
  private func rebuild() {
    var desiredKeys: Set<String> = []

    for screen in NSScreen.screens {
      guard let displayID = screen.displayID else { continue }

      let barRect = settings.hideNotch
        ? ScreenGeometry.barRect(
          frame: screen.frame, visibleFrame: screen.visibleFrame,
          safeAreaTop: screen.safeAreaInsets.top)
        : nil
      if let rect = barRect {
        let key = "\(displayID).bar"
        desiredKeys.insert(key)
        show(key: key, frame: rect) { BarWindow(frame: rect) }
      }

      let wantsCorners =
        settings.roundCorners
        && (settings.cornersOnAllDisplays || CGDisplayIsBuiltin(displayID) != 0)
      if wantsCorners {
        let rects = ScreenGeometry.cornerRects(
          frame: screen.frame, radius: CGFloat(settings.cornerRadius),
          topInset: barRect?.height ?? 0)
        for (corner, rect) in rects {
          let key = "\(displayID).\(corner.rawValue)"
          desiredKeys.insert(key)
          show(key: key, frame: rect) { CornerWindow(corner: corner, frame: rect) }
        }
      }
    }

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
