import Foundation

/// User preferences, persisted in `UserDefaults`.
@MainActor
final class AppSettings: ObservableObject {
  static let radiusRange: ClosedRange<Double> = 0...30

  private enum Key {
    static let hideNotch = "hideNotch"
    static let roundCorners = "roundCorners"
    static let cornerRadius = "cornerRadius"
    static let cornersOnAllDisplays = "cornersOnAllDisplays"
    static let showMenuBarIcon = "showMenuBarIcon"
  }

  private enum Default {
    static let hideNotch = true
    static let roundCorners = true
    static let cornerRadius: Double = 10
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

  @Published var cornerRadius: Double {
    didSet { defaults.set(cornerRadius, forKey: Key.cornerRadius) }
  }

  /// When false, corners are rounded on the built-in display only.
  @Published var cornersOnAllDisplays: Bool {
    didSet { defaults.set(cornersOnAllDisplays, forKey: Key.cornersOnAllDisplays) }
  }

  @Published var showMenuBarIcon: Bool {
    didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: [
      Key.hideNotch: Default.hideNotch,
      Key.roundCorners: Default.roundCorners,
      Key.cornerRadius: Default.cornerRadius,
      Key.cornersOnAllDisplays: Default.cornersOnAllDisplays,
      Key.showMenuBarIcon: Default.showMenuBarIcon,
    ])
    hideNotch = defaults.bool(forKey: Key.hideNotch)
    roundCorners = defaults.bool(forKey: Key.roundCorners)
    let storedRadius = defaults.double(forKey: Key.cornerRadius)
    cornerRadius = min(max(storedRadius, Self.radiusRange.lowerBound), Self.radiusRange.upperBound)
    cornersOnAllDisplays = defaults.bool(forKey: Key.cornersOnAllDisplays)
    showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
  }
}
