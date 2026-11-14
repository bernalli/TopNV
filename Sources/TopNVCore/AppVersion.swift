import Foundation

public struct AppVersion {
  public let title: String

  public init(shortVersion: String?, build: String?, localizer: Localizer = .main) {
    let version = Self.nonblank(shortVersion)
    let build = Self.nonblank(build)
    switch (version, build) {
    case (.some(let version), .some(let build)): title = localizer(.versionWithBuild, version, build)
    case (.some(let version), .none): title = localizer(.version, version)
    case (.none, .some(let build)): title = localizer(.versionUnavailableWithBuild, build)
    case (.none, .none): title = localizer(.versionUnavailable)
    }
  }

  private static func nonblank(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
    else { return nil }
    return value
  }
}
