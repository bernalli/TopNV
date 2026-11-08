import Foundation

public enum AppLink: String, CaseIterable {
  case releaseNotes = "https://github.com/bernalli/topNV/releases"
  case reportIssue = "https://github.com/bernalli/topNV/issues/new"
  case source = "https://github.com/bernalli/topNV"

  public var url: URL? { URL(string: rawValue) }
}
