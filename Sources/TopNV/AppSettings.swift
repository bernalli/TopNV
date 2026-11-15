import Foundation

/// User preferences, persisted in `UserDefaults`.
@MainActor
final class AppSettings: ObservableObject {
  /// Shared with the separate visibility model of the menu bar icon.
  nonisolated static let showMenuBarIconKey = "showMenuBarIcon"

  private enum Key {
    static let hideNotch = "hideNotch"
    static let roundCorners = "roundCorners"
    /// Written by versions before the radius was fixed at 15 points; removed at launch.
    static let legacyCornerRadius = "cornerRadius"
    static let cornersOnAllDisplays = "cornersOnAllDisplays"
    static let showMenuBarIcon = AppSettings.showMenuBarIconKey
  }

  private enum Default {
    static let hideNotch = true
    static let roundCorners = true
    static let cornersOnAllDisplays = false
    static let showMenuBarIcon = true
  }

  private let defaults: UserDefaults

  @Published var hideNotch: Bool {
    didSet { defaults.set(hideNotch, forKey: Key.hideNotch) }
  }

  @Published var roundCorners: Bool {
    didSet { defaults.set(roundCorners, forKey: Key.roundCorners) }
  }

  /// When false, corners are rounded on the built-in display only.
  @Published var cornersOnAllDisplays: Bool {
    didSet { defaults.set(cornersOnAllDisplays, forKey: Key.cornersOnAllDisplays) }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.removeObject(forKey: Key.legacyCornerRadius)
    defaults.register(defaults: [
      Key.hideNotch: Default.hideNotch,
      Key.roundCorners: Default.roundCorners,
      Key.cornersOnAllDisplays: Default.cornersOnAllDisplays,
      Key.showMenuBarIcon: Default.showMenuBarIcon,
    ])
    hideNotch = defaults.bool(forKey: Key.hideNotch)
    roundCorners = defaults.bool(forKey: Key.roundCorners)
    cornersOnAllDisplays = defaults.bool(forKey: Key.cornersOnAllDisplays)
  }
}
