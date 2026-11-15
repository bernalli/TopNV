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

  /// D-36: the version row shows the short version only, never the build number.
  func testVersionShowsOnlyTheShortVersion() {
    XCTAssertEqual(AppVersion(shortVersion: "1.1.0").title, "Version 1.1.0")
    XCTAssertEqual(AppVersion(shortVersion: "2.0").title, "Version 2.0")
    XCTAssertEqual(AppVersion(shortVersion: nil).title, "Version Unavailable")
  }

  func testBlankVersionIsMissingAndWhitespaceIsTrimmed() {
    XCTAssertEqual(AppVersion(shortVersion: " \n").title, "Version Unavailable")
    XCTAssertEqual(AppVersion(shortVersion: "").title, "Version Unavailable")
    XCTAssertEqual(AppVersion(shortVersion: " 1.1.0 ").title, "Version 1.1.0")
  }

  func testInformationWrapsAtWordsWithoutLosingTheNotice() {
    let notice = "Allow TopNV in System Settings > General > Login Items."
    XCTAssertEqual(
      MenuText.lines(notice),
      [
        "Allow TopNV in System Settings > General >", "Login Items.",
      ])
    XCTAssertEqual(MenuText.lines(notice).joined(separator: " "), notice)
    XCTAssertEqual(
      MenuText.lines("Open TopNV again to bring it back."),
      [
        "Open TopNV again to bring it back."
      ])
  }

  func testWrappingHandlesEmptyTextWhitespaceAndLongWords() {
    XCTAssertEqual(MenuText.lines(" \n\t"), [])
    XCTAssertEqual(MenuText.lines("a\n  bb\tccc", width: 4), ["a bb", "ccc"])
    XCTAssertEqual(MenuText.lines("abcdefghij end", width: 4), ["abcd", "efgh", "ij", "end"])
    XCTAssertEqual(MenuText.lines("ab", width: 0), ["a", "b"])
  }
}
