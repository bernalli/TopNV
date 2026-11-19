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
    XCTAssertEqual(options.map(\.gain), [3, 3, 3, 2.3, 1.9, 1.65])
    XCTAssertEqual(options.map(\.cutoff), [0.21, 0.21, 0.21, 0.255, 0.3, 0.345])
    XCTAssertEqual(options.map(\.curve), [nil, .soft, .strong, .soft, .soft, .soft])
    XCTAssertEqual(options.map(\.title), [
      "3 / 0.21 (1.2.5)", "3 / 0.21 + soft curve", "3 / 0.21 + strong curve",
      "2.3 / 0.255 + soft curve", "1.9 / 0.3 + soft curve", "1.65 / 0.345 + soft curve"
    ])
    // The raised black points stay under 0.7325, which was grey on the real bar (18-11).
    let blackPoints = options.map { $0.cutoff + 0.5 / $0.gain }
    XCTAssertEqual(blackPoints.map { ($0 * 100).rounded() / 100 }, [0.38, 0.38, 0.38, 0.47, 0.56, 0.65])
    for option in options {
      XCTAssertEqual(option.cutoff - 0.5 / option.gain, 0.04, accuracy: 0.005, option.title)
    }
    XCTAssertEqual(Set(options.map(\.command)).count, options.count)
    for option in options {
      XCTAssertEqual(KeyCalibration.option(for: option.command), option, option.title)
    }
    for command in [MenuCommand.hideNotch, .quit, .about] {
      XCTAssertNil(KeyCalibration.option(for: command))
    }
  }

  /// A test copy starts as production: with the first candidate, equal to the normal key.
  func testOnlyATestCopyStartsWithTheProductionCandidate() {
    XCTAssertEqual(KeyCalibration.initial(bundleIdentifier: testCopy), KeyCalibration.options[0])
    XCTAssertEqual(KeyCalibration.initial(bundleIdentifier: "com.example.other"), KeyCalibration.options[0])
    for identifier in [production, "IO.GITHUB.BERNALLI.TOPNV", "", nil] {
      XCTAssertNil(KeyCalibration.initial(bundleIdentifier: identifier), "\(String(describing: identifier))")
    }
  }

  func testACandidateReplacesOnlyTheNormalKey() {
    XCTAssertEqual(KeyCalibration.normalMatrix(nil), LuminanceKey.normal.matrix)
    for option in KeyCalibration.options {
      let matrix = KeyCalibration.normalMatrix(option)
      let row: [Float] = [
        -option.gain * 0.2126, -option.gain * 0.7152, -option.gain * 0.0722, 0,
        0.5 + option.gain * option.cutoff
      ]
      XCTAssertEqual(matrix, row + row + row + [0, 0, 0, 0, 1], option.title)
      XCTAssertEqual(matrix == LuminanceKey.normal.matrix, option.gain == 3 && option.cutoff == 0.21, option.title)
      XCTAssertEqual(KeyCalibration.normalCurve(option), option.curve, option.title)
    }
    XCTAssertEqual(KeyCalibration.normalMatrix(KeyCalibration.options[0]), LuminanceKey.normal.matrix)
    XCTAssertEqual(KeyCalibration.normalCurve(nil), LuminanceKey.normal.curve)
    XCTAssertNil(LuminanceKey.revealed.curve)
    XCTAssertEqual(LuminanceKey.revealed.gain, 6)
    XCTAssertEqual(LuminanceKey.revealed.cutoff, 0.2)
  }

  func testProductionHasNoCalibrationMenu() {
    let rows = MenuLayout.rows(for: state(KeyCalibration.initial(bundleIdentifier: production)))
    XCTAssertNil(calibrationMenu(rows))
    XCTAssertEqual(flattened(rows).filter { $0.id.hasPrefix("keyCalibration") }, [])
    XCTAssertEqual(rows, MenuLayout.rows(for: state(nil)))
  }

  func testInstantSwitchHintFollowsCalibrationOnlyInTestCopies() throws {
    for identifier in [production, production.uppercased(), "", nil] {
      let rows = MenuLayout.rows(for: state(KeyCalibration.initial(bundleIdentifier: identifier)))
      XCTAssertFalse(rows.contains { $0.id == "instantSwitch" })
    }
    let rows = MenuLayout.rows(for: state(KeyCalibration.initial(bundleIdentifier: testCopy)))
    let index = try XCTUnwrap(rows.firstIndex { $0.id == "keyCalibration" })
    let hint = try XCTUnwrap(rows.dropFirst(index + 1).first)
    XCTAssertEqual(hint.id, "instantSwitch")
    XCTAssertEqual(hint.kind, .info)
    XCTAssertEqual(hint.title, "Instant switch: Ctrl+Option+← →")
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
