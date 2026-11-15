import AppKit
import XCTest

@testable import TopNV

final class UpdateIntegrationTests: XCTestCase {
  private static let localization = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Localization")

  @MainActor func testSparkleUpdaterShowsUpdatesWithTheAppleStyleDriver() {
    let updater = SparkleUpdater()
    XCTAssertTrue(updater.userDriver is AppleStyleUpdateDriver)
  }

  /// The copied driver reads its own table from the bundle it gets; here the Italian folder.
  @MainActor func testTheDriverShowsItsTextsFromTheTopNVTable() throws {
    let path = Self.localization.appendingPathComponent("it.lproj").path
    let driver = AppleStyleUpdateDriver(
      appName: "TopNV", currentVersion: "1.2.0", strings: try XCTUnwrap(Bundle(path: path)),
      present: { _, _ in }, openURL: { _ in })

    driver.presentNotFound(reason: nil, description: "", acknowledgement: {})
    XCTAssertEqual(driver.alert?.messageText, "TopNV è aggiornato.")

    driver.presentUpdate(
      version: "1.2.1", informationOnly: false, infoURL: nil, userInitiated: true, reply: { _ in })
    XCTAssertEqual(driver.alert?.messageText, "È disponibile TopNV 1.2.1 (hai la 1.2.0).")
    XCTAssertEqual(driver.alert?.buttons.map(\.title), ["Installa e riavvia", "Più tardi"])
    driver.dismissUpdateInstallation()
    XCTAssertNil(driver.alert)
  }
}
