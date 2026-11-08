import Foundation

public enum AppLink: String, CaseIterable {
  case releaseNotes = "https://github.com/bernalli/TopNV/releases"
  case reportIssue = "https://github.com/bernalli/TopNV/issues/new"
  case source = "https://github.com/bernalli/TopNV"
  case sponsor = "https://github.com/sponsors/bernalli"

  public var url: URL? { URL(string: rawValue) }
}
