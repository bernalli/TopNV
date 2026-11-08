import Foundation
import CoreFoundation
import CryptoKit
#if canImport(FoundationXML)
import FoundationXML
#endif

public struct ReleaseViolation: Error, CustomStringConvertible, Equatable {
  public let code: String
  public let reason: String
  public var description: String { "\(code): \(reason)" }
  public init(_ code: String, _ reason: String) { self.code = code; self.reason = reason }
}

public struct AppcastMetadata: Equatable {
  public let version: String
  public let build: String
  public let minimum: String
  public let url: String
  public let length: Int64
  public let signature: Data
  public let notes: String
}

public enum ReleaseValidator {
  public static let stableFeed = "https://github.com/bernalli/TopNV/releases/latest/download/appcast.xml"
  public static let proofFeed = "https://github.com/bernalli/TopNV/releases/download/update-proof/appcast.xml"
  private static let ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
  private static func require(_ valid: Bool, _ code: String, _ reason: String) throws {
    if !valid { throw ReleaseViolation(code, reason) }
  }
  public static func number(_ value: String, positive: Bool = false) throws -> Int64 {
    try require(!value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }, "A16", "invalid integer grammar")
    guard let result = Int64(value), !positive || (result > 0 && !value.hasPrefix("0") && value.count <= 10) else {
      throw ReleaseViolation("A16", "integer outside allowed range")
    }
    return result
  }
  public static func version(_ value: String, minimum: Bool = false) throws -> [Int64] {
    let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
    try require(minimum ? (2...3).contains(pieces.count) : pieces.count == 3, "A16", "invalid version components")
    return try pieces.map { try number(String($0)) }
  }
  public static func boolean(_ value: Any?, equals expected: Bool) -> Bool {
    guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
    return value.boolValue == expected
  }
  private static func name(_ node: XMLNode) -> String {
    let local = node.localName ?? node.name ?? ""
    let uri = node.uri ?? ""
    return uri.isEmpty ? local : "{\(uri)}\(local)"
  }
  private static func children(_ node: XMLNode) throws -> [XMLElement] {
    var elements: [XMLElement] = []
    for child in node.children ?? [] {
      if let element = child as? XMLElement { elements.append(element) }
      else if child.kind == .comment { continue }
      else if child.kind == .text && (child.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
      else { throw ReleaseViolation("A14", "unexpected mixed content or processing instruction") }
    }
    return elements
  }
  private static func attributes(_ element: XMLElement, expected: Set<String>) throws -> [String: String] {
    var values: [String: String] = [:]
    for attribute in element.attributes ?? [] {
      let key = name(attribute)
      try require(values[key] == nil && expected.contains(key), "A15", "unexpected or repeated attribute")
      values[key] = attribute.stringValue ?? ""
    }
    try require(Set(values.keys) == expected, "A15", "missing attribute")
    return values
  }
  private static func scalar(_ element: XMLElement) throws -> String {
    try require((element.children ?? []).allSatisfy { $0.kind == .text || $0.kind == .comment }, "A15", "nested scalar content")
    let text = (element.children ?? []).filter { $0.kind == .text }.compactMap(\.stringValue).joined()
    try require(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "A15", "empty scalar")
    return text
  }
  public static func parse(_ data: Data) throws -> AppcastMetadata {
    try require(data.count <= 1_048_576, "A0", "appcast exceeds 1 MiB")
    guard let text = String(data: data, encoding: .utf8) else { throw ReleaseViolation("A0", "appcast must be UTF-8") }
    // Reject declarations before libxml sees them. Never resolve external entities.
    let declarationRemoved = text.replacingOccurrences(of: #"^\uFEFF?<\?xml\s[^?]*\?>"#, with: "", options: .regularExpression)
    try require(!text.localizedCaseInsensitiveContains("<!DOCTYPE") && !text.localizedCaseInsensitiveContains("<!ENTITY") && !declarationRemoved.contains("<?"), "A15", "forbidden XML declaration")
    let document: XMLDocument
    do { document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever, .nodePreserveAll]) }
    catch { throw ReleaseViolation("A0", "malformed XML") }
    let roots = try children(document)
    try require(roots.count == 1 && name(roots[0]) == "rss", "A1", "one unnamespaced rss required")
    let root = roots[0]
    try require(try attributes(root, expected: ["version"])["version"] == "2.0", "A14", "rss version must be 2.0")
    let channels = try children(root)
    try require(channels.count == 1 && name(channels[0]) == "channel", "A1", "one channel required")
    _ = try attributes(channels[0], expected: [])
    let channelFields = try children(channels[0])
    try require(channelFields.count == 2 && Set(channelFields.map(name)) == ["title", "item"], "A2", "channel requires one title and item")
    let channelTitle = channelFields.first { name($0) == "title" }!
    _ = try attributes(channelTitle, expected: []); _ = try scalar(channelTitle)
    let item = channelFields.first { name($0) == "item" }!
    _ = try attributes(item, expected: [])
    let s = "{\(ns)}"
    let expected: Set<String> = ["title", "pubDate", s + "version", s + "shortVersionString", s + "minimumSystemVersion", "description", "enclosure"]
    let fields = try children(item)
    try require(fields.count == expected.count && Set(fields.map(name)) == expected, "A14", "item fields missing, duplicate, or forbidden")
    var values: [String: String] = [:]
    var enclosure: [String: String] = [:]
    for field in fields {
      let fieldName = name(field)
      if fieldName == "enclosure" {
        enclosure = try attributes(field, expected: ["url", "length", "type", s + "edSignature"])
        try require(try children(field).isEmpty, "A15", "enclosure must be empty")
        try require(enclosure["type"] == "application/octet-stream", "A15", "wrong enclosure type")
      } else {
        let attrs = try attributes(field, expected: fieldName == "description" ? [s + "format"] : [])
        if fieldName == "description" { try require(attrs[s + "format"] == "markdown", "A13", "Markdown notes required") }
        values[fieldName] = try scalar(field)
      }
    }
    let build = values[s + "version"]!, version = values[s + "shortVersionString"]!, minimum = values[s + "minimumSystemVersion"]!
    _ = try number(build, positive: true); _ = try self.version(version); _ = try self.version(minimum, minimum: true)
    let length = try number(enclosure["length"]!)
    guard let signature = Data(base64Encoded: enclosure[s + "edSignature"]!), signature.count == 64 else { throw ReleaseViolation("A7", "invalid Ed25519 signature encoding") }
    let url = enclosure["url"]!
    guard let components = URLComponents(string: url), components.scheme == "https", components.host == "github.com",
          components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
          components.port == nil, !url.contains("%"), !url.contains(".."), !url.contains(where: { $0.isWhitespace }) else {
      throw ReleaseViolation("A3", "invalid download URL")
    }
    let stableURL = "https://github.com/bernalli/TopNV/releases/download/v\(version)/TopNV-\(version).dmg"
    let proofURL = "https://github.com/bernalli/TopNV/releases/download/update-proof/TopNV-\(version).dmg"
    try require(url == stableURL || url == proofURL, "A3", "download channel or filename mismatch")
    return AppcastMetadata(version: version, build: build, minimum: minimum, url: url, length: length, signature: signature, notes: values["description"]!)
  }
  public static func feed(appcast: Data, dmg: Data, info: [String: Any], tag: String, prefix: String, version: String, build: String, feed: String, publicKey: String) throws {
    let metadata = try parse(appcast)
    _ = try self.version(version); _ = try number(build, positive: true)
    let proof = tag == "update-proof"
    try require((proof || tag == "v" + version) && prefix == "https://github.com/bernalli/TopNV/releases/download/\(tag)/" && feed == (proof ? proofFeed : stableFeed), "A3", "inconsistent release channel")
    try require(metadata.url == prefix + "TopNV-\(version).dmg", "A3", "unexpected enclosure URL")
    try require(metadata.build == build && info["CFBundleVersion"] as? String == build, "A4", "build mismatch")
    try require(metadata.version == version && info["CFBundleShortVersionString"] as? String == version, "A5", "version mismatch")
    try require(metadata.length == Int64(dmg.count), "A6", "DMG length mismatch")
    guard let stored = info["SUPublicEDKey"] as? String, let bytes = Data(base64Encoded: stored), bytes.count == 32,
          stored == publicKey.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) else { throw ReleaseViolation("A9", "public key mismatch or encoding") }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: bytes)
    try require(key.isValidSignature(metadata.signature, for: dmg), "A8", "DMG signature invalid")
    try require(info["SUFeedURL"] as? String == feed, "A10", "bundle feed mismatch")
    try require(boolean(info["SUEnableAutomaticChecks"], equals: false) && boolean(info["SUAllowsAutomaticUpdates"], equals: false) && boolean(info["SUVerifyUpdateBeforeExtraction"], equals: true), "A11", "invalid bundle flags")
    try require(info["LSMinimumSystemVersion"] as? String == metadata.minimum, "A12", "minimum system version mismatch")
  }
  public static func order(build: String, version: String, current: Data?) throws {
    let proposedBuild = try number(build, positive: true), proposedVersion = try self.version(version)
    let old = try current.map(parse)
    let oldBuild = try old.map { try number($0.build, positive: true) } ?? 1
    let oldVersion = try old.map { try self.version($0.version) } ?? [1, 0, 0]
    try require(proposedBuild > oldBuild && oldVersion.lexicographicallyPrecedes(proposedVersion), old == nil ? "O0" : "O1", "build and version must both strictly increase")
  }
}
