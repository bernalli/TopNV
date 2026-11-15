import AppKit
import Combine
import TopNVCore

/// Reads the appearance macOS gives to the menu bar from a status item button: TopNV's own
/// item while it is visible, otherwise a zero-length item of its own. Since macOS 11 status
/// item buttons follow the menu bar, not the app, through `effectiveAppearance`.
@MainActor
final class MenuBarConditionsMonitor: NSObject, MenuBarConditionsSource {
  private enum Delay {
    /// Longer than the overlay's own wait, so the band is rebuilt before it is read.
    static let band: Duration = .seconds(1)
  }

  var onChange: (@MainActor () -> Void)?
  private let settings: AppSettings
  private let statusItem: NSStatusItem
  private let visibility: MenuVisibility
  /// The zero-length item, only while TopNV's own item is hidden.
  private(set) var probe: NSStatusItem?
  private(set) weak var observedButton: NSStatusBarButton?
  private var appearanceObservation: NSKeyValueObservation?
  private var subscriptions: Set<AnyCancellable> = []
  private let scheduleReport: GreyBarNoticeCoordinator.Schedule
  private var cancelReport: (() -> Void)?
  private var isSettling = false
  private var isStarted = false

  init(
    settings: AppSettings, statusItem: NSStatusItem, visibility: MenuVisibility,
    scheduleReport: @escaping GreyBarNoticeCoordinator.Schedule =
      GreyBarNoticeCoordinator.sleepSchedule
  ) {
    self.settings = settings
    self.statusItem = statusItem
    self.visibility = visibility
    self.scheduleReport = scheduleReport
    super.init()
  }

  var conditions: MenuBarConditions {
    let button = observedButton
    let screen = button?.window?.screen
    return MenuBarConditions(
      appearance: isSettling ? nil : button.flatMap { Self.appearance(of: $0.effectiveAppearance) },
      hidesNotch: settings.hideNotch,
      hasNotch: screen.map { ScreenGeometry.isNotched(safeAreaTop: $0.safeAreaInsets.top) }
        ?? false,
      isBandOnScreen: NSApplication.shared.windows.contains { $0 is BarWindow && $0.isVisible })
  }

  static func appearance(of appearance: NSAppearance) -> MenuBarAppearance? {
    switch appearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark]) {
    case .aqua?, .vibrantLight?: return .light
    case .darkAqua?, .vibrantDark?: return .dark
    default: return nil
    }
  }

  func start() {
    guard !isStarted else { return }
    isStarted = true
    // Invalidate before publication; read the new values after the band settles.
    visibility.objectWillChange.sink { [weak self] _ in
      MainActor.assumeIsolated { self?.reportAfterTheBand() }
      Task { @MainActor [weak self] in self?.followVisibility() }
    }.store(in: &subscriptions)
    settings.objectWillChange.sink { [weak self] _ in
      MainActor.assumeIsolated { self?.reportAfterTheBand() }
    }.store(in: &subscriptions)

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
    followVisibility()
  }

  func stop() {
    isStarted = false
    subscriptions.removeAll()
    NotificationCenter.default.removeObserver(self)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    cancelReport?()
    cancelReport = nil
    isSettling = false
    appearanceObservation = nil
    removeProbe()
    observedButton = nil
  }

  /// Observes TopNV's own button while the icon is visible, the zero-length item otherwise.
  func followVisibility() {
    guard isStarted else { return }
    let button: NSStatusBarButton?
    if visibility.isVisible {
      removeProbe()
      button = statusItem.button
    } else {
      if probe == nil {
        let item = NSStatusBar.system.statusItem(withLength: 0)
        item.button?.setAccessibilityElement(false)
        probe = item
      }
      button = probe?.button
    }
    if button !== observedButton || appearanceObservation == nil {
      observedButton = button
      appearanceObservation = button?.observe(\.effectiveAppearance, options: [.new]) {
        [weak self] _, _ in
        // AppKit updates this view on the main thread. Preserve intermediate changes
        // instead of rereading only the last appearance in a later task.
        MainActor.assumeIsolated { self?.report() }
      }
    }
    reportAfterTheBand()
  }

  private func removeProbe() {
    guard let probe else { return }
    if observedButton === probe.button {
      appearanceObservation = nil
      observedButton = nil
    }
    NSStatusBar.system.removeStatusItem(probe)
    self.probe = nil
  }

  @objc private func systemDidChange(_ notification: Notification) {
    reportAfterTheBand()
  }

  /// Invalidate immediately, then read again after the overlay has settled.
  private func reportAfterTheBand() {
    guard isStarted else { return }
    cancelReport?()
    isSettling = true
    report()
    cancelReport = scheduleReport(Delay.band) { [weak self] in
      guard let self, self.isStarted else { return }
      self.cancelReport = nil
      self.isSettling = false
      self.report()
    }
  }

  private func report() {
    onChange?()
  }
}
