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
  let testRoot = root.appendingPathComponent("build/ephemeral-roundtrip")
  try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
  let input = testRoot.appendingPathComponent("input")
  try FileManager.default.createDirectory(at: input, withIntermediateDirectories: false)
  defer { try? FileManager.default.removeItem(at: testRoot) }
  let dmg = root.appendingPathComponent("build/TopNV-0.0.1.dmg")
  try FileManager.default.copyItem(at: dmg, to: input.appendingPathComponent("TopNV-0.0.1.dmg"))
  try Data("Ephemeral signing round trip. Do not install.\n".utf8).write(
    to: input.appendingPathComponent("TopNV-0.0.1.md"))
  let key = Curve25519.Signing.PrivateKey()
  let encoded = Data(key.rawRepresentation.base64EncodedString().utf8)
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
  var info =
    try PropertyListSerialization.propertyList(
      from: Data(contentsOf: root.appendingPathComponent("build/TopNV.app/Contents/Info.plist")),
      format: nil) as! [String: Any]
  let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
  info["SUPublicEDKey"] = publicKey
  let feed = try Data(contentsOf: appcast)
  // The feed holds only a signature from the disposable key: show it to diagnose format changes.
  FileHandle.standardError.write(feed)
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
  let emptyOutput = testRoot.appendingPathComponent("empty.xml")
  var emptyArgs = args
  emptyArgs[emptyArgs.firstIndex(of: appcast.path)!] = emptyOutput.path
  let (emptyStatus, emptyLog) = try run(tool, emptyArgs, input: Data())
  try require(emptyStatus != 0 && emptyLog.range(of: encoded) == nil, "missing stdin key accepted")
  // Includes artifact candidates, build outputs and SwiftPM cache; report no secret bytes.
  try scan(root.appendingPathComponent("build"), forbidden: encoded)
  try scan(root.appendingPathComponent(".build"), forbidden: encoded)
  print(
    "PASS ephemeral stdin signing, CryptoKit verification, negative inputs and secret non-persistence"
  )
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
