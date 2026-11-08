import XCTest
import CryptoKit
@testable import TopNVReleaseCheck

final class AppcastCheckTests: XCTestCase {
  static let ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
  static let prefix = "https://github.com/bernalli/TopNV/releases/download/v1.1.0/"
  static let feed = "https://github.com/bernalli/TopNV/releases/latest/download/appcast.xml"
  let key = Curve25519.Signing.PrivateKey() // Ephemeral, memory only.
  let payload = Data("disk image fixture".utf8)
  func xml() throws -> String {
    let signature = try key.signature(for: payload).base64EncodedString()
    return """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="\(Self.ns)"><channel><title>TopNV</title><item>
    <title>1.1.0</title><pubDate>Sun, 08 Nov 2026 12:00:00 +0000</pubDate>
    <sparkle:version>2</sparkle:version><sparkle:shortVersionString>1.1.0</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    <description sparkle:format="markdown"><![CDATA[Update **notes**]]></description>
    <enclosure url="\(Self.prefix)TopNV-1.1.0.dmg" length="\(payload.count)" type="application/octet-stream" sparkle:edSignature="\(signature)"/>
    </item></channel></rss>
    """
  }
  func plist() -> [String: Any] {
    ["CFBundleVersion": "2", "CFBundleShortVersionString": "1.1.0", "LSMinimumSystemVersion": "14.0",
     "SUPublicEDKey": key.publicKey.rawRepresentation.base64EncodedString(), "SUFeedURL": Self.feed,
     "SUEnableAutomaticChecks": false, "SUAllowsAutomaticUpdates": false, "SUVerifyUpdateBeforeExtraction": true]
  }
  func check(_ xml: String, payload: Data? = nil, info: [String: Any]? = nil, publicKey: String? = nil) throws {
    try ReleaseValidator.feed(appcast: Data(xml.utf8), dmg: payload ?? self.payload, info: info ?? plist(),
      tag: "v1.1.0", prefix: Self.prefix, version: "1.1.0", build: "2", feed: Self.feed,
      publicKey: publicKey ?? key.publicKey.rawRepresentation.base64EncodedString())
  }
  func testValidFeedAndEquivalentNamespaces() throws {
    let source = try xml(); try check(source)
    try check(source.replacingOccurrences(of: "sparkle:", with: "s:").replacingOccurrences(of: "xmlns:sparkle", with: "xmlns:s"))
    try check(source.replacingOccurrences(of: "<title>1.1.0</title>", with: "").replacingOccurrences(of: "</item>", with: "<title>1.1.0</title></item>"))
    try check(source.replacingOccurrences(of: "<item>", with: "<!-- comment --><item>"))
  }
  func testEverySingletonDuplicateAndMissingRejected() throws {
    let source = try xml()
    let pattern = #"<(title|pubDate|sparkle:version|sparkle:shortVersionString|sparkle:minimumSystemVersion|description)\b[^>]*>.*?</\1>|<enclosure\b[^>]*/>"#
    let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
    let item = String(source.components(separatedBy: "<item>")[1].components(separatedBy: "</item>")[0])
    for match in regex.matches(in: item, range: NSRange(item.startIndex..., in: item)) {
      let field = String(item[Range(match.range, in: item)!])
      XCTAssertThrowsError(try check(source.replacingOccurrences(of: field, with: "")), field)
      for extra in [field, field.replacingOccurrences(of: ">2<", with: ">3<")] {
        for insertion in ["<item>", "</item>"] {
          let replacement = insertion == "<item>" ? insertion + extra : extra + insertion
          XCTAssertThrowsError(try check(source.replacingOccurrences(of: insertion, with: replacement)), field)
        }
      }
    }
    for (old, new) in [("</channel>", "<title>x</title></channel>"), ("</rss>", "<channel><title>x</title></channel></rss>"), ("</channel>", "<item/></channel>")] {
      XCTAssertThrowsError(try check(source.replacingOccurrences(of: old, with: new)))
    }
  }
  func testForbiddenStructureAndMetadata() throws {
    let source = try xml()
    for mutation in [
      ("<rss ", "<rss xml:lang=\"en\" "), ("<channel>", "<channel extra=\"x\">"), ("<item>", "<item x=\"x\">"),
      ("<title>1.1.0", "<title a=\"b\">1.1.0"), ("<title>1.1.0</title>", "<title>one<b/>two</title>"),
      ("<title>1.1.0</title>", "<title> </title>"), ("<item>", "<item>mixed"),
      ("<enclosure ", "<enclosure sparkle:version=\"2\" "), ("application/octet-stream", "application/zip"),
      ("sparkle:format=\"markdown\"", "sparkle:format=\"html\""), (Self.ns, "https://wrong.test"),
      ("<item>", "<item xmlns=\"urn:wrong\">"), ("<sparkle:version>", "<sparkle:version xmlns:sparkle=\"urn:wrong\">"),
      (">2</sparkle:version>", ">9223372036854775808</sparkle:version>"), (">2</sparkle:version>", "> 2</sparkle:version>"),
      (">1.1.0</sparkle:shortVersionString>", ">9223372036854775808.0.0</sparkle:shortVersionString>"),
      ("length=\"17\"", "length=\"9223372036854775808\""), ("TopNV-1.1.0.dmg\"", "TopNV-1.1.0.dmg?q=1\"")
    ] { XCTAssertThrowsError(try check(source.replacingOccurrences(of: mutation.0, with: mutation.1)), "\(mutation)") }
    for name in ["criticalUpdate", "informationalUpdate", "deltas", "channel", "maximumSystemVersion", "unknown"] {
      XCTAssertThrowsError(try check(source.replacingOccurrences(of: "</item>", with: "<sparkle:\(name)>x</sparkle:\(name)></item>")))
    }
    for insertion in ["<!DOCTYPE rss SYSTEM 'file:///no-such-file'>", "<!DOCTYPE rss [<!ENTITY x SYSTEM 'https://invalid.test/'>]>", "<?probe value?>"] {
      XCTAssertThrowsError(try check(source.replacingOccurrences(of: "<rss ", with: insertion + "<rss ")))
    }
    XCTAssertThrowsError(try check(source + String(repeating: " ", count: 1_048_576)))
    // Every truncation before the root closing tag must fail, not pick partial metadata.
    let close = source.range(of: "</rss>")!.upperBound
    for end in source.indices where end < close { XCTAssertThrowsError(try check(String(source[..<end]))) }
  }
  func testEverySignatureBitAndPayloadByteIsAuthenticated() throws {
    let source = try xml(); let sig = try key.signature(for: payload)
    for bit in 0..<(sig.count * 8) {
      var changed = sig; changed[bit / 8] ^= UInt8(1 << (bit % 8))
      XCTAssertThrowsError(try check(source.replacingOccurrences(of: sig.base64EncodedString(), with: changed.base64EncodedString())))
    }
    for index in payload.indices { var changed = payload; changed[index] ^= 1; XCTAssertThrowsError(try check(source, payload: changed)) }
    XCTAssertThrowsError(try check(source, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()))
  }
  func testPlistTypesAndChannelMismatch() throws {
    let source = try xml()
    for field in plist().keys { var p=plist(); p.removeValue(forKey: field); XCTAssertThrowsError(try check(source, info: p)) }
    for field in ["SUEnableAutomaticChecks", "SUAllowsAutomaticUpdates", "SUVerifyUpdateBeforeExtraction"] {
      for invalid: Any in [NSNumber(value: 0), NSNumber(value: 1), "false", NSNull()] {
        var p=plist(); p[field]=invalid; XCTAssertThrowsError(try check(source, info: p))
      }
    }
    XCTAssertThrowsError(try ReleaseValidator.feed(appcast: Data(source.utf8), dmg: payload, info: plist(), tag: "update-proof", prefix: Self.prefix, version: "1.1.0", build: "2", feed: Self.feed, publicKey: key.publicKey.rawRepresentation.base64EncodedString()))
  }
  func testCLIRejectsAmbiguity() throws {
    XCTAssertThrowsError(try ReleaseArguments(["order", "--build", "2", "--build", "3", "--version", "1.1.0", "--no-current-feed"]))
    XCTAssertThrowsError(try ReleaseArguments(["order", "--build", "2", "--version", "1.1.0", "--no-current-feed", "--current-feed", "x"]))
    for args in [["bad"], ["feed", "--unknown", "x"], ["order", "--build"], ["order", "--no-current-feed"]] { XCTAssertThrowsError(try ReleaseArguments(args)) }
  }
}
