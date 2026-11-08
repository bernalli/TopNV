import Foundation

public enum AppLink: String, CaseIterable {
  case releaseNotes = "https://github.com/bernalli/topNV/releases"
  case reportIssue = "https://github.com/bernalli/topNV/issues/new"
  case source = "https://github.com/bernalli/topNV"
  case sponsor = "https://github.com/sponsors/bernalli"

  public var url: URL? { URL(string: rawValue) }
}
