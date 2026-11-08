import Foundation

public struct AppVersion {
  public let title: String

  public init(shortVersion: String?, build: String?) {
    let version = Self.nonblank(shortVersion)
    let build = Self.nonblank(build)
    let label = version.map { "Version \($0)" } ?? "Version Unavailable"
    title = build.map { "\(label) (\($0))" } ?? label
  }

  private static func nonblank(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
    else { return nil }
    return value
  }
}
