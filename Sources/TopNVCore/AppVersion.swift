import Foundation

/// The version line of the menu and of the About window. The build number is never shown (D-36);
/// CFBundleVersion stays in Info.plist, where Sparkle reads it.
public struct AppVersion {
  public let title: String

  public init(shortVersion: String?, localizer: Localizer = .main) {
    guard let version = Self.nonblank(shortVersion) else {
      title = localizer(.versionUnavailable)
      return
    }
    title = localizer(.version, version)
  }

  private static func nonblank(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
    else { return nil }
    return value
  }
}
