import XCTest

@testable import TopNVCore

final class MenuPresentationTests: XCTestCase {
  func testStatusReflectsEverySettingsCombination() {
    let cases = [
      (true, true, "Notch Hidden, Corners Rounded", "display"),
      (true, false, "Notch Hidden", "menubar.rectangle"),
      (false, true, "Corners Rounded", "rectangle"),
      (false, false, "Inactive", "power"),
    ]
    for (notch, corners, title, symbol) in cases {
      let status = MenuStatus(hideNotch: notch, roundCorners: corners)
      XCTAssertEqual(status.title, title)
      XCTAssertEqual(status.symbol, symbol)
    }
  }

  func testVersionIncludesAvailableBundleFields() {
    XCTAssertEqual(AppVersion(shortVersion: "1.1.0", build: "1").title, "Version 1.1.0 (1)")
    XCTAssertEqual(AppVersion(shortVersion: "2.0", build: nil).title, "Version 2.0")
    XCTAssertEqual(AppVersion(shortVersion: nil, build: "7").title, "Version Unavailable (7)")
    XCTAssertEqual(AppVersion(shortVersion: nil, build: nil).title, "Version Unavailable")
  }

  func testBlankVersionFieldsAreMissingAndWhitespaceIsTrimmed() {
    XCTAssertEqual(AppVersion(shortVersion: " \n", build: "").title, "Version Unavailable")
    XCTAssertEqual(AppVersion(shortVersion: " 1.1.0 ", build: " 1\n").title, "Version 1.1.0 (1)")
  }

  func testInformationWrapsAtWordsWithoutLosingTheNotice() {
    let notice = "Allow topNV in System Settings > General > Login Items."
    XCTAssertEqual(MenuText.lines(notice), [
      "Allow topNV in System Settings > General >", "Login Items.",
    ])
    XCTAssertEqual(MenuText.lines(notice).joined(separator: " "), notice)
    XCTAssertEqual(MenuText.lines("Open topNV again to bring it back."), [
      "Open topNV again to bring it back.",
    ])
  }

  func testWrappingHandlesEmptyTextWhitespaceAndLongWords() {
    XCTAssertEqual(MenuText.lines(" \n\t"), [])
    XCTAssertEqual(MenuText.lines("a\n  bb\tccc", width: 4), ["a bb", "ccc"])
    XCTAssertEqual(MenuText.lines("abcdefghij end", width: 4), ["abcd", "efgh", "ij", "end"])
    XCTAssertEqual(MenuText.lines("ab", width: 0), ["a", "b"])
  }
}
