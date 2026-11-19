import XCTest
@testable import TopNVCore

/// The key calibration exists only in test copies, never under the production bundle identifier.
final class KeyCalibrationTests: XCTestCase {
  private let production = "io.github.bernalli.topnv"
  private let testCopy = "io.github.bernalli.topnv.try125"

  private func state(_ calibration: KeyCalibration?) -> MenuState {
    MenuState(
      hideNotch: true, roundCorners: true, cornersOnAllDisplays: false, launchAtLogin: false,
      loginNeedsApproval: false, loginError: nil,
      updates: .ready(canCheck: true, checksAutomatically: false), keyCalibration: calibration)
  }

  private func calibrationMenu(_ rows: [MenuRow]) -> [MenuRow]? {
    for row in rows where row.id == "keyCalibration" {
      if case .submenu(let children, true) = row.kind { return children }
    }
    return nil
  }

  private func flattened(_ rows: [MenuRow]) -> [MenuRow] {
    rows.flatMap { row -> [MenuRow] in
      if case .submenu(let children, _) = row.kind { return [row] + flattened(children) }
      return [row]
    }
  }

  func testTheCandidatesInOrder() {
    let options = KeyCalibration.options
    XCTAssertEqual(options.map(\.gain), [12, 6, 4.5, 3.6, 3, 2.4])
    XCTAssertEqual(options.map(\.cutoff), [0.228, 0.2, 0.2, 0.19, 0.21, 0.25])
    XCTAssertEqual(options.map(\.title), [
      "12 / 0.228 (1.2.4)", "6 / 0.2", "4.5 / 0.2", "3.6 / 0.19", "3 / 0.21", "2.4 / 0.25"
    ])
    XCTAssertEqual(Set(options.map(\.command)).count, options.count)
    for option in options {
      XCTAssertEqual(KeyCalibration.option(for: option.command), option, option.title)
    }
    for command in [MenuCommand.hideNotch, .quit, .about] {
      XCTAssertNil(KeyCalibration.option(for: command))
    }
  }

  /// A test copy starts as production: with the fifth candidate, equal to the normal key.
  func testOnlyATestCopyStartsWithTheProductionCandidate() {
    XCTAssertEqual(KeyCalibration.initial(bundleIdentifier: testCopy), KeyCalibration.options[4])
    XCTAssertEqual(KeyCalibration.initial(bundleIdentifier: "com.example.other"), KeyCalibration.options[4])
    for identifier in [production, "IO.GITHUB.BERNALLI.TOPNV", "", nil] {
      XCTAssertNil(KeyCalibration.initial(bundleIdentifier: identifier), "\(String(describing: identifier))")
    }
  }

  func testACandidateReplacesTheNormalKey() {
    XCTAssertEqual(KeyCalibration.normalMatrix(nil), LuminanceKey.normal.matrix)
    for option in KeyCalibration.options {
      let matrix = KeyCalibration.normalMatrix(option)
      let row: [Float] = [
        -option.gain * 0.2126, -option.gain * 0.7152, -option.gain * 0.0722, 0,
        0.5 + option.gain * option.cutoff
      ]
      XCTAssertEqual(matrix, row + row + row + [0, 0, 0, 0, 1], option.title)
      XCTAssertEqual(matrix == LuminanceKey.normal.matrix, option == KeyCalibration.options[4], option.title)
    }
    XCTAssertEqual(KeyCalibration.normalMatrix(KeyCalibration.options[4]), LuminanceKey.normal.matrix)
  }

  func testProductionHasNoCalibrationMenu() {
    let rows = MenuLayout.rows(for: state(KeyCalibration.initial(bundleIdentifier: production)))
    XCTAssertNil(calibrationMenu(rows))
    XCTAssertEqual(flattened(rows).filter { $0.id.hasPrefix("keyCalibration") }, [])
    XCTAssertEqual(rows, MenuLayout.rows(for: state(nil)))
  }

  func testATestCopyChecksTheChosenCandidate() throws {
    for selected in KeyCalibration.options {
      let rows = MenuLayout.rows(for: state(selected))
      let menu = try XCTUnwrap(calibrationMenu(rows), selected.title)
      let toggles = menu.compactMap { row -> (MenuCommand, Bool)? in
        if case .toggle(let command, let isOn, true) = row.kind { return (command, isOn) }
        return nil
      }
      XCTAssertEqual(toggles.map(\.0), KeyCalibration.options.map(\.command))
      XCTAssertEqual(toggles.filter(\.1).map(\.0), [selected.command])
      XCTAssertEqual(menu.compactMap { $0.kind == .info ? $0.title : nil }, ["Gain / cutoff of the normal key"])
      let ids = flattened(rows).map(\.id)
      XCTAssertEqual(Set(ids).count, ids.count)
      // The calibration follows Options, inside the first group.
      XCTAssertEqual(rows.map(\.id).firstIndex(of: "keyCalibration"),
                     try XCTUnwrap(rows.map(\.id).firstIndex(of: "options")) + 1)
      let title = try XCTUnwrap(rows.first { $0.id == "keyCalibration" }).title
      XCTAssertEqual(title, "Key calibration")
    }
  }
}
