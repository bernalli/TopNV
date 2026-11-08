import Foundation

public struct ReleaseArguments {
  public let command: String
  public let values: [String: String]
  public init(_ arguments: [String]) throws {
    guard let command = arguments.first, ["feed", "order"].contains(command) else { throw ReleaseViolation("CLI", "expected feed or order") }
    let required: Set<String> = command == "feed" ? ["--appcast", "--dmg", "--app", "--tag", "--prefix", "--version", "--build", "--feed", "--public-key-file"] : ["--build", "--version"]
    let allowed = required.union(command == "order" ? ["--current-feed", "--no-current-feed"] : [])
    var values: [String: String] = [:], index = 1
    while index < arguments.count {
      let option = arguments[index]
      guard allowed.contains(option), values[option] == nil else { throw ReleaseViolation("CLI", "unknown or repeated option") }
      if option == "--no-current-feed" { values[option] = ""; index += 1 }
      else {
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--"), !arguments[index + 1].isEmpty else { throw ReleaseViolation("CLI", "missing option value") }
        values[option] = arguments[index + 1]; index += 2
      }
    }
    guard required.isSubset(of: Set(values.keys)), command != "order" || ((values["--current-feed"] != nil) != (values["--no-current-feed"] != nil)) else { throw ReleaseViolation("CLI", "missing or conflicting mode") }
    self.command = command; self.values = values
  }
  public func run() throws {
    func data(_ key: String) throws -> Data { try Data(contentsOf: URL(fileURLWithPath: values[key]!)) }
    if command == "order" {
      try ReleaseValidator.order(build: values["--build"]!, version: values["--version"]!, current: values["--current-feed"] == nil ? nil : data("--current-feed"))
    } else {
      let plistURL = URL(fileURLWithPath: values["--app"]!).appendingPathComponent("Contents/Info.plist")
      guard let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as? [String: Any] else { throw ReleaseViolation("CLI", "invalid app plist") }
      let publicKey = try String(contentsOfFile: values["--public-key-file"]!, encoding: .utf8)
      try ReleaseValidator.feed(appcast: data("--appcast"), dmg: data("--dmg"), info: plist, tag: values["--tag"]!, prefix: values["--prefix"]!, version: values["--version"]!, build: values["--build"]!, feed: values["--feed"]!, publicKey: publicKey)
    }
  }
}
