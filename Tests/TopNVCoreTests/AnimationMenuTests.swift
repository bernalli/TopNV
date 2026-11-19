import XCTest
@testable import TopNVCore

final class AnimationMenuTests: XCTestCase {
  private func state(bundle: String?) -> MenuState {
    MenuState(hideNotch: true, roundCorners: false, cornersOnAllDisplays: false,
              launchAtLogin: false, loginNeedsApproval: false, loginError: nil, updates: .hidden,
              isTestCopy: TestCopy.matches(bundle))
  }

  func testTestCopyHasNoKeyCalibrationMenu() {
    XCTAssertFalse(MenuLayout.rows(for: state(bundle: "test.copy")).contains { $0.id == "keyCalibration" })
  }

  func testPreviewIsAbsentFromProductionAndUnidentifiedCopies() {
    for bundle in [nil, "", "IO.GITHUB.BERNALLI.TOPNV"] {
      XCTAssertFalse(MenuLayout.rows(for: state(bundle: bundle)).contains { $0.id == "animationPreview" })
    }
  }

  func testPreviewOffersOnlyTheCalmEntrance() throws {
    var menu = state(bundle: "test.copy")
    let calm = MenuRow(id: "previewCalm", title: "Scorrimento calmo — fable", symbol: nil,
                       kind: .action(.previewCalm, enabled: true, key: ""))
    XCTAssertEqual(MenuCommand.previewCalm.rawValue, "fable-scorrimento-calmo")
    for hasBand in [true, false] {
      menu.hideNotch = hasBand
      let row = try XCTUnwrap(MenuLayout.rows(for: menu).first { $0.id == "animationPreview" })
      XCTAssertEqual(row.title, "Animation preview")
      XCTAssertEqual(row.kind, .submenu([calm], enabled: hasBand))
    }
  }
}
