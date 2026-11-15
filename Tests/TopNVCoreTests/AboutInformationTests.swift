import XCTest

@testable import TopNVCore

final class AboutInformationTests: XCTestCase {
  func testBundleFieldsSupplyNameVersionAndCopyright() {
    let information = AboutInformation(infoDictionary: [
      "CFBundleName": "Example App",
      "CFBundleShortVersionString": "1.1.0",
      "CFBundleVersion": "1",
      "NSHumanReadableCopyright": "Copyright (c) 2026. All rights reserved.",
    ])
    XCTAssertEqual(information.name, "Example App")
    XCTAssertEqual(information.version.title, "Version 1.1.0")
    XCTAssertEqual(information.copyright, "Copyright (c) 2026. All rights reserved.")
  }

  func testUnbundledInformationOmitsCopyrightAndUsesFallbacks() {
    let information = AboutInformation(infoDictionary: nil)
    XCTAssertEqual(information.name, "TopNV")
    XCTAssertEqual(information.version.title, "Version Unavailable")
    XCTAssertNil(information.copyright)
    XCTAssertNil(AboutInformation(infoDictionary: [:]).copyright)
  }

  /// D-36: the build number is never shown, even when it is the only field present.
  func testTheBuildNumberIsNeverShown() {
    for build: Any in ["7", " 7\n", 7] {
      XCTAssertEqual(
        AboutInformation(infoDictionary: ["CFBundleVersion": build]).version.title,
        "Version Unavailable")
    }
  }

  func testMissingBlankOrNonStringCopyrightOmitsTheRow() {
    for value: Any in ["", " \n\t", 42] {
      XCTAssertNil(AboutInformation(infoDictionary: ["NSHumanReadableCopyright": value]).copyright)
    }
  }

  func testMetadataTrimsOuterWhitespaceAndPreservesCopyrightLines() {
    let information = AboutInformation(infoDictionary: [
      "CFBundleName": " Example App \n",
      "CFBundleShortVersionString": " 1.1.0 ",
      "CFBundleVersion": " 1\n",
      "NSHumanReadableCopyright": " \nCopyright (c) 2026\nAll rights reserved. \n",
    ])
    XCTAssertEqual(information.name, "Example App")
    XCTAssertEqual(information.version.title, "Version 1.1.0")
    XCTAssertEqual(information.copyright, "Copyright (c) 2026\nAll rights reserved.")
  }

  func testBlankOrNonStringNameUsesFallback() {
    for value: Any in ["", " \n\t", 42] {
      XCTAssertEqual(AboutInformation(infoDictionary: ["CFBundleName": value]).name, "TopNV")
    }
  }
}
