import XCTest

@testable import TopNVCore

/// The About window stays in English in every language (D-35); the menu stays translated.
final class AboutTextTests: XCTestCase {
  private static let localization = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Localization")

  func testTheEnglishLocalizerReadsNoTable() {
    for key in TextKey.allCases where !key.rawValue.contains("%") {
      XCTAssertEqual(Localizer.english(key), key.rawValue)
    }
    XCTAssertEqual(Localizer.english(.about, "TopNV"), "About TopNV")
    XCTAssertEqual(Localizer.english(.versionWithBuild, "1.2.0", "7"), "Version 1.2.0 (7)")
  }

  func testAboutTextsAreEnglish() {
    XCTAssertEqual(AboutText.windowTitle, "About TopNV")
    XCTAssertEqual(AboutText.gitHubHelp, "View TopNV on GitHub")
    XCTAssertEqual(AboutText.sponsor, "Buy Me a Coffee")
    let information = AboutInformation(
      infoDictionary: ["CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "7"],
      localizer: AboutText.localizer)
    XCTAssertEqual(information.version.title, "Version 1.2.0 (7)")
  }

  /// The menu still shows About and the version in the system language.
  func testTheMenuKeepsItsTranslatedAboutAndVersion() throws {
    let italian = Localizer(
      bundle: try XCTUnwrap(Bundle(path: Self.localization.appendingPathComponent("it.lproj").path))
    )
    XCTAssertEqual(italian(.about, "TopNV"), "Informazioni su TopNV")
    XCTAssertEqual(italian(.versionWithBuild, "1.2.0", "7"), "Versione 1.2.0 (7)")
  }

  /// Texts that only the About window shows have no entry in any table.
  func testAboutOnlyTextsAreNotInTheTables() throws {
    for language in ["en", "it", "es", "fr", "de", "pt-BR", "ja", "zh-Hans"] {
      let table = try String(
        contentsOf: Self.localization.appendingPathComponent(
          "\(language).lproj/Localizable.strings"),
        encoding: .utf8)
      XCTAssertFalse(table.contains("\"View %@ on GitHub\""), language)
      XCTAssertFalse(table.contains("\"Buy Me a Coffee\""), language)
    }
  }
}
