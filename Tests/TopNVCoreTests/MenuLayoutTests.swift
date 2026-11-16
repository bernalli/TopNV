import XCTest

@testable import TopNVCore

/// The approved menu tree, checked on every state the menu can show and in every language.
final class MenuLayoutTests: XCTestCase {
  private static let localization = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Localization")
  private static let languages = ["en", "it", "es", "fr", "de", "pt-BR", "ja", "zh-Hans"]
  private static let longError = String(
    repeating: "The login item could not be registered. ", count: 4)
  private static let loginErrors: [String?] = [
    nil, "", "   ", "\n\t ", "Operation not permitted.", longError,
  ]
  private static let updateStates: [UpdateItems] = [
    .hidden, .waiting,
    .ready(canCheck: true, checksAutomatically: true),
    .ready(canCheck: true, checksAutomatically: false),
    .ready(canCheck: false, checksAutomatically: true),
    .ready(canCheck: false, checksAutomatically: false),
  ]
  private let english = Localizer(bundle: .main)

  private static func state(
    hideNotch: Bool = true, roundCorners: Bool = true, cornersOnAllDisplays: Bool = false,
    launchAtLogin: Bool = false, loginNeedsApproval: Bool = false, loginError: String? = nil,
    updates: UpdateItems = .ready(canCheck: true, checksAutomatically: false), blackMenuBar: Bool = true
  ) -> MenuState {
    MenuState(
      hideNotch: hideNotch, roundCorners: roundCorners, cornersOnAllDisplays: cornersOnAllDisplays,
      launchAtLogin: launchAtLogin, loginNeedsApproval: loginNeedsApproval, loginError: loginError,
      updates: updates, blackMenuBar: blackMenuBar)
  }

  /// Six switches, six login errors and six updater states: 2304 states.
  private static var everyState: [MenuState] {
    var states: [MenuState] = []
    for mask in 0..<(1 << 6) {
      func bit(_ index: Int) -> Bool { mask & (1 << index) != 0 }
      for error in loginErrors {
        for updates in updateStates {
          states.append(
            state(
              hideNotch: bit(0), roundCorners: bit(1), cornersOnAllDisplays: bit(2),
              launchAtLogin: bit(3), loginNeedsApproval: bit(4), loginError: error,
              updates: updates, blackMenuBar: bit(5)))
        }
      }
    }
    return states
  }

  private func rows(_ state: MenuState, _ localizer: Localizer? = nil) -> [MenuRow] {
    MenuLayout.rows(for: state, localizer: localizer ?? english)
  }

  private static func options(in rows: [MenuRow]) -> [MenuRow] {
    for row in rows where row.id == "options" {
      if case .submenu(let children, _) = row.kind { return children }
    }
    return []
  }

  private static func row(_ id: String, in rows: [MenuRow]) -> MenuRow? {
    rows.first { $0.id == id }
  }

  private static func hasLoginProblem(_ state: MenuState) -> Bool {
    state.loginNeedsApproval
      || !(state.loginError ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// The ids of one level, with the rows of one caption (`x.caption.0`, `x.caption.1`…) as one entry.
  private static func collapsed(_ ids: [String]) -> [String] {
    var result: [String] = []
    for id in ids {
      var name = id
      if let range = id.range(of: #"\.caption\.[0-9]+$"#, options: .regularExpression) {
        name = String(id[..<range.lowerBound]) + ".caption"
      }
      if name.hasSuffix(".caption"), result.last == name { continue }
      result.append(name)
    }
    return result
  }

  /// The top level of the approved tree, written from the tree and not from MenuLayout.
  private static func expectedTop(_ state: MenuState) -> [String] {
    var ids = [
      "topnv", "hideNotch", "roundCorners", "separator.options", "options", "separator.app",
      "about",
    ]
    if state.updates != .hidden { ids.append("check") }
    return ids + ["report", "separator.quit", "quit"]
  }

  /// Options of the approved tree.
  private static func expectedOptions(_ state: MenuState) -> [String] {
    var ids = ["blackMenuBar", "cornersOnAllDisplays", "options.separator.login", "login"]
    if hasLoginProblem(state) { ids.append("login.caption") }
    if state.updates != .hidden { ids.append("automatic") }
    return ids + ["options.separator", "hide", "hide.caption"]
  }

  /// Problems with the separators of one menu level.
  static func separatorProblems(_ level: [MenuRow]) -> [String] {
    var problems: [String] = []
    if level.first?.kind == .separator { problems.append("first") }
    if level.last?.kind == .separator { problems.append("last") }
    for (left, right) in zip(level, level.dropFirst())
    where left.kind == .separator && right.kind == .separator {
      problems.append("double at \(right.id)")
    }
    for row in level where row.kind == .separator && (!row.title.isEmpty || row.symbol != nil) {
      problems.append("separator \(row.id) has content")
    }
    return problems
  }

  // MARK: Structure

  func testTheTreeIsTheApprovedOneInEveryState() {
    for current in Self.everyState {
      let top = rows(current)
      let options = Self.options(in: top)
      XCTAssertEqual(top.map(\.id), Self.expectedTop(current), "\(current)")
      XCTAssertEqual(Self.collapsed(options.map(\.id)), Self.expectedOptions(current), "\(current)")
      for prefix in ["login.caption.", "hide.caption."] {
        let ids = options.map(\.id).filter { $0.hasPrefix(prefix) }
        XCTAssertEqual(ids, ids.indices.map { "\(prefix)\($0)" }, "\(current)")
      }
    }
  }

  func testTheSeparatorCheckFindsMalformedLevels() {
    let item = MenuRow(
      id: "a", title: "A", symbol: nil, kind: .action(.about, enabled: true, key: ""))
    func line(_ id: String, title: String = "") -> MenuRow {
      MenuRow(id: id, title: title, symbol: nil, kind: .separator)
    }
    XCTAssertEqual(Self.separatorProblems([item, line("s"), item]), [])
    XCTAssertEqual(Self.separatorProblems([]), [])
    XCTAssertEqual(Self.separatorProblems([line("s"), item]), ["first"])
    XCTAssertEqual(Self.separatorProblems([item, line("s")]), ["last"])
    XCTAssertEqual(Self.separatorProblems([item, line("s"), line("t"), item]), ["double at t"])
    XCTAssertEqual(
      Self.separatorProblems([item, line("s", title: "x"), item]), ["separator s has content"])
  }

  func testSeparatorsAreNeverFirstLastOrDoubledInEveryState() {
    for current in Self.everyState {
      let top = rows(current)
      XCTAssertEqual(Self.separatorProblems(top), [], "\(current)")
      XCTAssertEqual(Self.separatorProblems(Self.options(in: top)), [], "\(current)")
    }
  }

  // MARK: Items

  func testTheSwitchesAndCommandsFollowTheState() {
    for current in Self.everyState {
      let top = rows(current)
      let options = Self.options(in: top)
      func kind(_ id: String) -> MenuRow.Kind? {
        (Self.row(id, in: top) ?? Self.row(id, in: options))?.kind
      }
      XCTAssertEqual(kind("hideNotch"), .toggle(.hideNotch, isOn: current.hideNotch, enabled: true))
      XCTAssertEqual(kind("blackMenuBar"),
                     .toggle(.blackMenuBar, isOn: current.blackMenuBar, enabled: current.hideNotch))
      XCTAssertEqual(
        kind("roundCorners"), .toggle(.roundCorners, isOn: current.roundCorners, enabled: true))
      XCTAssertEqual(
        kind("cornersOnAllDisplays"),
        .toggle(
          .cornersOnAllDisplays, isOn: current.cornersOnAllDisplays, enabled: current.roundCorners))
      XCTAssertEqual(
        kind("login"), .toggle(.launchAtLogin, isOn: current.launchAtLogin, enabled: true))
      XCTAssertEqual(kind("hide"), .action(.hideMenuBarIcon, enabled: true, key: ""))
      XCTAssertEqual(kind("about"), .action(.about, enabled: true, key: ""))
      XCTAssertEqual(kind("report"), .action(.reportIssue, enabled: true, key: ""))
      XCTAssertEqual(kind("quit"), .action(.quit, enabled: true, key: "q"))
      if case .submenu(_, let enabled)? = kind("options") {
        XCTAssertTrue(enabled)
      } else {
        XCTFail("Options is not a submenu")
      }
      switch current.updates {
      case .hidden:
        XCTAssertNil(kind("check"))
        XCTAssertNil(kind("automatic"))
      case .waiting:
        XCTAssertEqual(kind("check"), .action(.checkForUpdates, enabled: false, key: ""))
        XCTAssertEqual(kind("automatic"), .toggle(.automaticUpdates, isOn: false, enabled: false))
      case .ready(let canCheck, let automatic):
        XCTAssertEqual(kind("check"), .action(.checkForUpdates, enabled: canCheck, key: ""))
        XCTAssertEqual(
          kind("automatic"), .toggle(.automaticUpdates, isOn: automatic, enabled: true))
      }
      let withKeys = (top + options).compactMap { row -> String? in
        if case .action(_, _, let key) = row.kind, !key.isEmpty { return row.id }
        return nil
      }
      XCTAssertEqual(withKeys, ["quit"])
    }
  }

  func testGreyRowsOnlyForALoginProblemAndTheIconRecovery() {
    for current in Self.everyState {
      let top = rows(current)
      let options = Self.options(in: top)
      XCTAssertFalse(top.contains { $0.kind == .info }, "\(current)")
      let info = options.filter { $0.kind == .info }
      XCTAssertTrue(
        info.allSatisfy { $0.id.hasPrefix("login.caption.") || $0.id.hasPrefix("hide.caption.") },
        "\(current)")
      XCTAssertTrue(info.allSatisfy { $0.title.count <= 44 && $0.symbol == nil }, "\(current)")
      let login = info.filter { $0.id.hasPrefix("login.caption.") }.map(\.title)
        .joined(separator: " ")
      let error = (current.loginError ?? "").split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
      if !error.isEmpty {
        XCTAssertEqual(login, error)
      } else if current.loginNeedsApproval {
        XCTAssertEqual(login, "Allow TopNV in System Settings > General > Login Items.")
      } else {
        XCTAssertEqual(login, "", "no grey row while the login item works")
      }
      XCTAssertEqual(
        info.filter { $0.id.hasPrefix("hide.caption.") }.map(\.title).joined(separator: " "),
        "Open TopNV again to bring it back.")
    }
  }

  func testTheLoginItemSaysWhenApprovalIsPending() {
    for current in Self.everyState {
      XCTAssertEqual(
        Self.row("login", in: Self.options(in: rows(current)))?.title,
        current.loginNeedsApproval ? "Launch at Login (Requires Approval)" : "Launch at Login")
    }
  }

  func testTitlesAndSymbolsOfTheMenu() {
    let top = rows(Self.state())
    let options = Self.options(in: top)
    let expected: [(String, String, String?)] = [
      ("topnv", "TopNV", nil), ("hideNotch", "Hide Notch", "menubar.rectangle"),
      ("roundCorners", "Round Corners", "rectangle"), ("options", "Options", "gearshape"),
      ("about", "About TopNV", nil), ("check", "Check for Updates…", nil),
      ("report", "Report an Issue…", nil), ("quit", "Quit TopNV", nil),
      ("cornersOnAllDisplays", "Round Corners on All Displays", "display.2"),
      ("blackMenuBar", "Black menu bar on light wallpapers", "menubar.rectangle"),
      ("login", "Launch at Login", "power"),
      ("automatic", "Check for Updates Automatically", "arrow.triangle.2.circlepath"),
      ("hide", "Hide Menu Bar Icon", "menubar.rectangle"),
      ("hide.caption.0", "Open TopNV again to bring it back.", nil),
    ]
    for (id, title, symbol) in expected {
      let found = Self.row(id, in: top) ?? Self.row(id, in: options)
      XCTAssertEqual(found?.title, title, id)
      XCTAssertEqual(found?.symbol, symbol, id)
    }
    XCTAssertEqual(Self.row("topnv", in: top)?.kind, .header)
  }

  func testTheRowsTakenOutOfTheMenuAreGone() {
    let removedIDs = ["status", "details", "display", "permissions", "macOS", "version"]
    let removedTexts = [
      "Notch Hidden", "Corners Rounded", "Inactive", "Details", "Applies", "Permissions",
      "Requires macOS", "Version", "Automatic Updates",
    ]
    for current in Self.everyState {
      let top = rows(current)
      for row in top + Self.options(in: top) {
        let base = row.id.split(separator: ".").first.map(String.init) ?? row.id
        XCTAssertFalse(removedIDs.contains(base), row.id)
        XCTAssertNotEqual(row.title, "Corners on All Displays", row.id)
        for text in removedTexts {
          XCTAssertFalse(row.title.contains(text), "\(row.id): \(row.title)")
        }
      }
    }
  }

  func testIdsAreUniqueAndTitlesAreNotBlankInEveryState() {
    for current in Self.everyState {
      let top = rows(current)
      let all = top + Self.options(in: top)
      let ids = all.map(\.id)
      XCTAssertEqual(Set(ids).count, ids.count, "\(current)")
      for row in all where row.kind != .separator {
        XCTAssertFalse(row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, row.id)
        XCTAssertFalse(row.id.lowercased().contains("radius"), row.id)
        XCTAssertFalse(row.title.lowercased().contains("radius"), row.title)
      }
    }
  }

  // MARK: Languages

  func testEveryLanguageGivesTheSameTree() throws {
    let errors: [String?] = [nil, "Operation not permitted."]
    for language in Self.languages {
      let path = Self.localization.appendingPathComponent("\(language).lproj").path
      let localizer = Localizer(bundle: try XCTUnwrap(Bundle(path: path), language))
      for current in Self.everyState where errors.contains(current.loginError) {
        let top = rows(current, localizer)
        let options = Self.options(in: top)
        XCTAssertEqual(top.map(\.id), Self.expectedTop(current), language)
        XCTAssertEqual(Self.collapsed(options.map(\.id)), Self.expectedOptions(current), language)
        for row in top + options where row.kind != .separator {
          XCTAssertFalse(
            row.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "\(language) \(row.id)")
          if row.kind == .info {
            XCTAssertLessThanOrEqual(row.title.count, 44, "\(language) \(row.id)")
          }
        }
      }
      if language != "en" {
        for key in [
          TextKey.blackMenuBar, .roundCornersOnAllDisplays, .launchAtLoginNeedsApproval,
          .checkForUpdatesAutomatically,
        ] {
          XCTAssertNotEqual(localizer(key), key.rawValue, "\(language): \(key.rawValue)")
        }
      }
    }
  }

  // MARK: Information rows

  func testALongLoginErrorIsSplitIntoShortRows() {
    let captions = Self.options(in: rows(Self.state(loginError: Self.longError)))
      .filter { $0.id.hasPrefix("login.caption.") }
    XCTAssertGreaterThan(captions.count, 1)
    XCTAssertTrue(captions.allSatisfy { $0.title.count <= 44 && $0.kind == .info && $0.symbol == nil })
    XCTAssertEqual(
      captions.map(\.title).joined(separator: " "),
      Self.longError.split(whereSeparator: \.isWhitespace).joined(separator: " "))
  }

  func testOnlyTheFirstLineOfAnInformationRowCarriesTheSymbol() throws {
    let long = MenuLayout.info(
      String(repeating: "word ", count: 30), id: "x", symbol: "display")
    XCTAssertGreaterThan(long.count, 1)
    XCTAssertEqual(long.first?.symbol, "display")
    XCTAssertTrue(long.dropFirst().allSatisfy { $0.symbol == nil })
    XCTAssertEqual(long.map(\.id), long.indices.map { "x.\($0)" })
    XCTAssertTrue(MenuLayout.info("  ", id: "blank").isEmpty)
  }
}
