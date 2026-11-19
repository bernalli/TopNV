import XCTest
@testable import TopNVCore

final class AnimationMenuTests: XCTestCase {
  private func state(bundle: String?, selection: BarAnimation? = nil) -> MenuState {
    var state = MenuState(hideNotch: true, roundCorners: false, cornersOnAllDisplays: false,
                          launchAtLogin: false, loginNeedsApproval: false, loginError: nil, updates: .hidden,
                          isTestCopy: TestCopy.matches(bundle))
    state.lastAnimation = selection
    return state
  }

  func testTestCopyHasNoKeyCalibrationMenu() {
    XCTAssertFalse(MenuLayout.rows(for: state(bundle: "test.copy")).contains { $0.id == "keyCalibration" })
  }

  func testPreviewIsAbsentFromProductionAndUnidentifiedCopies() {
    for bundle in [nil, "", "IO.GITHUB.BERNALLI.TOPNV"] {
      XCTAssertFalse(MenuLayout.rows(for: state(bundle: bundle)).contains { $0.id == "animationPreview" })
    }
  }

  func testPreviewListsEightCommandsAndReplayRequiresASelectionAndBand() throws {
    var menu = state(bundle: "test.copy")
    func children() throws -> [MenuRow] {
      let row = try XCTUnwrap(MenuLayout.rows(for: menu).first { $0.id == "animationPreview" })
      guard case .submenu(let children, let enabled) = row.kind else { return [] }
      XCTAssertEqual(enabled, menu.hideNotch)
      return children
    }
    let rows = try children()
    XCTAssertEqual(rows.count, 9)
    XCTAssertEqual(rows.first?.title, "Sipario di velluto — astra")
    XCTAssertEqual(rows.last?.kind, .action(.replayAnimation, enabled: false, key: ""))
    for (row, variant) in zip(rows, BarAnimation.allCases) {
      guard case .toggle(let command, false, true) = row.kind else { return XCTFail(row.id) }
      XCTAssertEqual(command.rawValue, variant.rawValue)
    }
    menu.lastAnimation = .wave
    XCTAssertEqual(try children().last?.kind, .action(.replayAnimation, enabled: true, key: ""))
    menu.hideNotch = false
    _ = try children()
  }
}
