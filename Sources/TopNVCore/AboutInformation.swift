import Foundation

public struct AboutInformation {
  public let name: String
  public let version: AppVersion
  public let copyright: String?

  public init(infoDictionary: [String: Any]?, localizer: Localizer = .main) {
    name = Self.nonblank(infoDictionary?["CFBundleName"] as? String) ?? "TopNV"
    version = AppVersion(
      shortVersion: infoDictionary?["CFBundleShortVersionString"] as? String, localizer: localizer)
    copyright = Self.nonblank(infoDictionary?["NSHumanReadableCopyright"] as? String)
  }

  private static func nonblank(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
    else { return nil }
    return value
  }
}
