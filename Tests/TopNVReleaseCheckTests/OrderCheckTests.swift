import XCTest
@testable import TopNVReleaseCheck

final class OrderCheckTests: XCTestCase {
  func testBootstrapRequiresBothNumbersToIncrease() {
    for version in ["0.9.9", "1.0.0", "1.0.1"] {
      for build in ["0", "1", "2"] {
        if version == "1.0.1" && build == "2" { XCTAssertNoThrow(try ReleaseValidator.order(build: build, version: version, current: nil)) }
        else { XCTAssertThrowsError(try ReleaseValidator.order(build: build, version: version, current: nil)) }
      }
    }
  }
  func testVersionsCompareNumericallyByComponent() throws {
    let source = try AppcastCheckTests().xml()
      .replacingOccurrences(of: ">1.1.0</sparkle:shortVersionString>", with: ">1.9.0</sparkle:shortVersionString>")
      .replacingOccurrences(of: "v1.1.0/TopNV-1.1.0.dmg", with: "v1.9.0/TopNV-1.9.0.dmg")
    let current = Data(source.utf8)
    XCTAssertNoThrow(try ReleaseValidator.order(build: "3", version: "1.10.0", current: current))
    XCTAssertThrowsError(try ReleaseValidator.order(build: "3", version: "1.8.99", current: current))
  }
  func testCurrentFeedMustBeUnambiguousAndStrictlyOlder() throws {
    let source = try AppcastCheckTests().xml()
    let data = Data(source.utf8)
    XCTAssertNoThrow(try ReleaseValidator.order(build: "3", version: "1.2.0", current: data))
    for (build, version) in [("2","1.2.0"), ("3","1.1.0"), ("1","1.2.0"), ("3","1.0.9")] {
      XCTAssertThrowsError(try ReleaseValidator.order(build: build, version: version, current: data))
    }
    XCTAssertThrowsError(try ReleaseValidator.order(build: "3", version: "1.2.0", current: Data(source.replacingOccurrences(of: "</item>", with: "<sparkle:version>2</sparkle:version></item>").utf8)))
  }
}
