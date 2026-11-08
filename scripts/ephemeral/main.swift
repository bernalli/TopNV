import CryptoKit
// CI-only round trip. The disposable seed never leaves memory or stdin.
import Foundation

func require(_ condition: Bool, _ reason: String) throws {
  if !condition { throw ReleaseViolation("EPHEMERAL", reason) }
}
func run(_ tool: URL, _ args: [String], input: Data) throws -> (Int32, Data) {
  let process = Process()
  let stdin = Pipe()
  let output = Pipe()
  process.executableURL = tool
  process.arguments = args
  var environment = ProcessInfo.processInfo.environment
  environment.removeValue(forKey: "SPARKLE_ED_PRIVATE_KEY")
  process.environment = environment
  process.standardInput = stdin
  process.standardOutput = output
  process.standardError = output
  try process.run()
  stdin.fileHandleForWriting.write(input)
  try stdin.fileHandleForWriting.close()
  let text = output.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  return (process.terminationStatus, text)
}
// Packaging commands never receive a key, so their output is safe to print.
func runPackaging(_ path: String, _ args: [String]) throws {
  let (status, output) = try run(URL(fileURLWithPath: path), args, input: Data())
  if status != 0 { FileHandle.standardError.write(output) }
  try require(status == 0, "\(path) exited with status \(status)")
}
func scan(_ root: URL, forbidden: Data) throws {
  guard
    let iterator = FileManager.default.enumerator(
      at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
  else { return }
  for case let url as URL in iterator {
    let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
    guard properties.isRegularFile == true, properties.isSymbolicLink != true else { continue }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var tail = Data()
    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
      let data = tail + chunk
      try require(
        data.range(of: forbidden) == nil,
        "disposable secret found in generated files; value withheld")
      tail = Data(data.suffix(forbidden.count - 1))
    }
  }
}

do {
  let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  let tool = root.appendingPathComponent(".build/artifacts/sparkle/Sparkle/bin/generate_appcast")
  let testRoot = root.appendingPathComponent("build/ephemeral-roundtrip-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
  defer {
    do {
      try FileManager.default.removeItem(at: testRoot)
    } catch {
      FileHandle.standardError.write(Data("Ephemeral cleanup failed; output withheld\n".utf8))
      exit(1)
    }
  }
  let input = testRoot.appendingPathComponent("input")
  try FileManager.default.createDirectory(at: input, withIntermediateDirectories: false)
  try Data("Ephemeral signing round trip. Do not install.\n".utf8).write(
    to: input.appendingPathComponent("TopNV-0.0.1.md"))
  let key = Curve25519.Signing.PrivateKey()
  let encoded = Data(key.rawRepresentation.base64EncodedString().utf8)
  let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
  // generate_appcast signs only when the key matches SUPublicEDKey inside the archive. On a
  // mismatch it exits 0 with an unsigned feed, so the round trip packages a copy of the app that
  // carries the disposable public key. The production key takes no part in this check.
  let stage = testRoot.appendingPathComponent("stage")
  try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
  let app = stage.appendingPathComponent("TopNV.app")
  try FileManager.default.copyItem(
    at: root.appendingPathComponent("build/TopNV.app"), to: app)
  let plist = app.appendingPathComponent("Contents/Info.plist")
  guard
    var info =
      try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil)
      as? [String: Any]
  else {
    throw ReleaseViolation("EPHEMERAL", "bundle plist must be a dictionary")
  }
  info["SUPublicEDKey"] = publicKey
  try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(
    to: plist)
  try FileManager.default.createSymbolicLink(
    at: stage.appendingPathComponent("Applications"),
    withDestinationURL: URL(fileURLWithPath: "/Applications"))
  try runPackaging(
    "/usr/bin/codesign", ["--force", "--sign", "-", "--timestamp=none", app.path])
  let dmg = input.appendingPathComponent("TopNV-0.0.1.dmg")
  try runPackaging(
    "/usr/bin/hdiutil",
    [
      "create", "-volname", "TopNV", "-srcfolder", stage.path, "-fs", "HFS+", "-format", "UDZO",
      dmg.path,
    ])
  let appcast = testRoot.appendingPathComponent("appcast.xml")
  let prefix = "https://github.com/bernalli/TopNV/releases/download/v0.0.1/"
  let args = [
    "--ed-key-file", "-", "--embed-release-notes", "--download-url-prefix", prefix, "-o",
    appcast.path, input.path,
  ]
  try require(
    !args.contains(where: { $0.contains(String(decoding: encoded, as: UTF8.self)) }),
    "secret in argv")
  let (status, output) = try run(tool, args, input: encoded + Data([10]))
  try require(
    output.range(of: encoded) == nil, "tool output contains the disposable key; output withheld")
  if status != 0 { FileHandle.standardError.write(output) }
  try require(status == 0, "generate_appcast exited with status \(status)")
  let feed = try Data(contentsOf: appcast)
  let payload = try Data(contentsOf: dmg)
  func validate(_ feed: Data, _ publicKey: String) throws {
    try ReleaseValidator.feed(
      appcast: feed, dmg: payload, info: info, tag: "v0.0.1", prefix: prefix, version: "0.0.1",
      build: "1", feed: ReleaseValidator.stableFeed, publicKey: publicKey)
  }
  try validate(feed, publicKey)
  var rejected = false
  do {
    try validate(
      feed, Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString())
  } catch { rejected = true }
  try require(rejected, "wrong public key accepted")
  let metadata = try ReleaseValidator.parse(feed)
  var bad = metadata.signature
  bad[0] ^= 1
  let badFeed = Data(
    String(decoding: feed, as: UTF8.self).replacingOccurrences(
      of: metadata.signature.base64EncodedString(), with: bad.base64EncodedString()
    ).utf8)
  rejected = false
  do { try validate(badFeed, publicKey) } catch { rejected = true }
  try require(rejected, "altered signature accepted")
  // A key that does not match the packaged public key must never produce an accepted feed.
  let otherKey = Data(
    Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString().utf8)
  let mismatchOutput = testRoot.appendingPathComponent("mismatch.xml")
  var mismatchArgs = args
  mismatchArgs[mismatchArgs.firstIndex(of: appcast.path)!] = mismatchOutput.path
  try require(
    !FileManager.default.fileExists(atPath: mismatchOutput.path), "stale mismatch output")
  let (mismatchStatus, mismatchLog) = try run(tool, mismatchArgs, input: otherKey + Data([10]))
  try require(
    mismatchLog.range(of: otherKey) == nil,
    "tool output contains the disposable key; output withheld")
  try require(mismatchStatus == 0, "unexpected mismatch tool failure; output withheld")
  let mismatchFeed = try Data(contentsOf: mismatchOutput)
  rejected = false
  do {
    try validate(mismatchFeed, publicKey)
  } catch let violation as ReleaseViolation {
    try require(
      violation == ReleaseViolation("A15", "missing attribute"),
      "unexpected mismatch rejection")
    rejected = true
  }
  try require(rejected, "mismatched signing key accepted")
  // Restoring only the known-good signature must make this feed valid.
  let mismatchDocument = try XMLDocument(
    data: mismatchFeed, options: [.nodeLoadExternalEntitiesNever, .nodePreserveAll])
  let enclosures = try mismatchDocument.nodes(forXPath: "/rss/channel/item/enclosure")
  guard enclosures.count == 1, let enclosure = enclosures[0] as? XMLElement else {
    throw ReleaseViolation("EPHEMERAL", "unexpected mismatch enclosure")
  }
  let signatureAttribute = XMLNode(kind: .attribute)
  signatureAttribute.name = "sparkle:edSignature"
  signatureAttribute.uri = "http://www.andymatuschak.org/xml-namespaces/sparkle"
  signatureAttribute.stringValue = metadata.signature.base64EncodedString()
  enclosure.addAttribute(signatureAttribute)
  try validate(mismatchDocument.xmlData, publicKey)
  let emptyOutput = testRoot.appendingPathComponent("empty.xml")
  var emptyArgs = args
  emptyArgs[emptyArgs.firstIndex(of: appcast.path)!] = emptyOutput.path
  let (emptyStatus, emptyLog) = try run(tool, emptyArgs, input: Data())
  try require(emptyStatus != 0 && emptyLog.range(of: encoded) == nil, "missing stdin key accepted")
  // Includes artifact candidates, build outputs and SwiftPM cache; report no secret bytes.
  for secret in [encoded, otherKey] {
    try scan(root.appendingPathComponent("build"), forbidden: secret)
    try scan(root.appendingPathComponent(".build"), forbidden: secret)
    try scan(
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Sparkle_generate_appcast"), forbidden: secret)
  }
} catch let violation as ReleaseViolation {
  // Violations carry fixed text and never echo values from the feed or the key.
  FileHandle.standardError.write(
    Data("Ephemeral signing check failed: \(violation)\n".utf8))
  exit(1)
} catch {
  FileHandle.standardError.write(
    Data("Ephemeral signing check failed: \(type(of: error))\n".utf8))
  exit(1)
}
print(
  "PASS ephemeral stdin signing, CryptoKit verification, negative inputs and secret non-persistence"
)
