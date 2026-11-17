import XCTest

@testable import TopNV

final class AppSettingsTests: XCTestCase {
  private var suiteName = ""
  private var defaults: UserDefaults!

  override func setUpWithError() throws {
    suiteName = "AppSettingsTests.\(UUID().uuidString)"
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suiteName)
    defaults = nil
  }

  /// The radius is fixed at 15 points; a value saved by an earlier version is removed at launch.
  @MainActor func testBlackMenuBarDefaultsOnAndPersistsOff() {
    let settings = AppSettings(defaults: defaults)
    XCTAssertTrue(settings.blackMenuBar)
    settings.blackMenuBar = false
    XCTAssertFalse(AppSettings(defaults: defaults).blackMenuBar)
    settings.blackMenuBar = true
    XCTAssertTrue(AppSettings(defaults: defaults).blackMenuBar)
  }

  @MainActor func testAStoredCornerRadiusIsRemovedAtLaunch() {
    defaults.set(30.0, forKey: "cornerRadius")
    XCTAssertNotNil(defaults.object(forKey: "cornerRadius"))

    _ = AppSettings(defaults: defaults)

    XCTAssertNil(defaults.object(forKey: "cornerRadius"))
  }

  @MainActor func testLaunchWithoutAStoredRadiusKeepsTheOtherSettings() {
    defaults.set(false, forKey: "hideNotch")

    let settings = AppSettings(defaults: defaults)

    XCTAssertNil(defaults.object(forKey: "cornerRadius"))
    XCTAssertFalse(settings.hideNotch)
    XCTAssertTrue(settings.roundCorners)
    XCTAssertFalse(settings.cornersOnAllDisplays)
  }
}
