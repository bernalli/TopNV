import XCTest
@testable import TopNVCore

final class UpdateConfigurationTests: XCTestCase {
  static var valid: [String: Any] {
    ["SUFeedURL": "https://github.com/bernalli/TopNV/releases/latest/download/appcast.xml",
     "SUPublicEDKey": Data(repeating: 0, count: 32).base64EncodedString(),
     "SUEnableAutomaticChecks": false, "SUAllowsAutomaticUpdates": false, "SUVerifyUpdateBeforeExtraction": true]
  }
  func testRequiresEveryFieldAndStrictBooleanTypes() {
    XCTAssertFalse(UpdateConfiguration(infoDictionary: nil).isValid)
    XCTAssertFalse(UpdateConfiguration(infoDictionary: [:]).isValid)
    XCTAssertTrue(UpdateConfiguration(infoDictionary: Self.valid).isValid)
    for field in Self.valid.keys { var info=Self.valid; info.removeValue(forKey: field); XCTAssertFalse(UpdateConfiguration(infoDictionary: info).isValid) }
    for field in ["SUEnableAutomaticChecks", "SUAllowsAutomaticUpdates", "SUVerifyUpdateBeforeExtraction"] {
      for value in [NSNumber(value: 0), NSNumber(value: 1), "false", NSNull(), !(Self.valid[field] as! Bool)] as [Any] {
        var info=Self.valid; info[field]=value; XCTAssertFalse(UpdateConfiguration(infoDictionary: info).isValid)
      }
    }
  }
  func testRejectsInvalidFeedsAndPublicKeys() {
    for url in ["", "http://github.com/feed", "https:///feed", "https://user:pass@github.com/feed", "not a URL", "https://github.com/a b"] {
      var info=Self.valid; info["SUFeedURL"]=url; XCTAssertFalse(UpdateConfiguration(infoDictionary: info).isValid, url)
    }
    for key in ["", "!", Data(repeating: 0,count: 31).base64EncodedString(), Data(repeating: 0,count: 33).base64EncodedString()] {
      var info=Self.valid; info["SUPublicEDKey"]=key; XCTAssertFalse(UpdateConfiguration(infoDictionary: info).isValid)
    }
  }
}
