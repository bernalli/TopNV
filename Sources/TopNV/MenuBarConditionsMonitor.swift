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
  private var pendingReport: Task<Void, Never>?
  private var isStarted = false

  init(settings: AppSettings, statusItem: NSStatusItem, visibility: MenuVisibility) {
    self.settings = settings
    self.statusItem = statusItem
    self.visibility = visibility
    super.init()
  }

  var conditions: MenuBarConditions {
    let button = observedButton
    let screen = button?.window?.screen
    return MenuBarConditions(
      appearance: button.flatMap { Self.appearance(of: $0.effectiveAppearance) },
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
    // objectWillChange fires before the new value is stored, so both read it a turn later.
    visibility.objectWillChange.sink { [weak self] _ in
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
    pendingReport?.cancel()
    pendingReport = nil
    appearanceObservation = nil
    removeProbe()
  }

  /// Observes TopNV's own button while the icon is visible, the zero-length item otherwise.
  func followVisibility() {
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
        Task { @MainActor [weak self] in self?.report() }
      }
    }
    report()
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

  /// The overlay rebuilds the band a little after a change; the report waits for it.
  private func reportAfterTheBand() {
    pendingReport?.cancel()
    pendingReport = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: Delay.band)
      } catch {
        return  // Cancelled by a newer change.
      }
      self?.report()
    }
  }

  private func report() {
    onChange?()
  }
}
