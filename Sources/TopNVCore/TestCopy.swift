/// Unidentified executables use the production menu.
public enum TestCopy {
  public static func matches(_ bundleIdentifier: String?) -> Bool {
    guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
    return bundleIdentifier.lowercased() != "io.github.bernalli.topnv"
  }
}
