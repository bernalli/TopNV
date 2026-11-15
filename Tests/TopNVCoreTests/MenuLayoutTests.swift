import XCTest

@testable import TopNVCore

final class MenuLayoutTests: XCTestCase {
  private let english = Localizer(bundle: .main)

  private func state(
    hideNotch: Bool = true, roundCorners: Bool = true, cornersOnAllDisplays: Bool = false,
    launchAtLogin: Bool = false, loginNeedsApproval: Bool = false, loginError: String? = nil,
    updatesAvailable: Bool = true, canCheckForUpdates: Bool = true,
    automaticUpdates: Bool = false, menuVisible: Bool = true
  ) -> MenuState {
    MenuState(
      hideNotch: hideNotch, roundCorners: roundCorners,
      cornersOnAllDisplays: cornersOnAllDisplays, launchAtLogin: launchAtLogin,
      loginNeedsApproval: loginNeedsApproval, loginError: loginError,
      updatesAvailable: updatesAvailable, canCheckForUpdates: canCheckForUpdates,
      automaticUpdates: automaticUpdates, menuVisible: menuVisible,
      versionTitle: "Version 1.2.0 (7)")
  }

  private func rows(_ state: MenuState) -> [MenuRow] {
    MenuLayout.rows(for: state, localizer: english)
  }

  private func children(_ id: String, in rows: [MenuRow]) -> [MenuRow]? {
    for row in rows where row.id == id {
      if case .submenu(let children, _) = row.kind { return children }
    }
    return nil
  }

  private func row(_ id: String, in rows: [MenuRow]) -> MenuRow? {
    rows.first { $0.id == id }
  }

  private func allRows(_ rows: [MenuRow]) -> [MenuRow] {
    rows.flatMap { row -> [MenuRow] in
      if case .submenu(let children, _) = row.kind { return [row] + allRows(children) }
      return [row]
    }
  }

  /// Every combination of the nine switches of `MenuState`.
  private var everyState: [MenuState] {
    (0..<(1 << 9)).map { mask in
      func bit(_ index: Int) -> Bool { mask & (1 << index) != 0 }
      return state(
        hideNotch: bit(0), roundCorners: bit(1), cornersOnAllDisplays: bit(2),
        launchAtLogin: bit(3), loginNeedsApproval: bit(4), updatesAvailable: bit(5),
        canCheckForUpdates: bit(6), automaticUpdates: bit(7), menuVisible: bit(8))
    }
  }

  // MARK: Order and content

  func testTheMenuHasTheOrderOfMonoPods() throws {
    let rows = rows(state())
    XCTAssertEqual(
      rows.map(\.id),
      [
        "topnv", "status.0", "hideNotch", "roundCorners", "details", "options",
        "separator.app", "version.0", "check", "about", "report", "separator.quit", "quit",
      ])
    XCTAssertEqual(
      try XCTUnwrap(children("details", in: rows)).map(\.id),
      ["display.0", "permissions.0", "macOS.0"])
    XCTAssertEqual(
      try XCTUnwrap(children("options", in: rows)).map(\.id),
      [
        "cornersOnAllDisplays", "login", "login.caption.0", "automatic", "options.separator",
        "hide", "hide.caption.0",
      ])
  }

  func testTitlesAndSymbolsAreTheOnesOfTheMenu() throws {
    let rows = rows(state())
    XCTAssertEqual(rows[0], MenuRow(id: "topnv", title: "TopNV", symbol: nil, kind: .header))
    XCTAssertEqual(
      rows[1],
      MenuRow(
        id: "status.0", title: "Notch Hidden, Corners Rounded", symbol: "display", kind: .info))
    XCTAssertEqual(row("hideNotch", in: rows)?.title, "Hide Notch")
    XCTAssertEqual(row("hideNotch", in: rows)?.symbol, "menubar.rectangle")
    XCTAssertEqual(row("roundCorners", in: rows)?.title, "Round Corners")
    XCTAssertEqual(row("roundCorners", in: rows)?.symbol, "rectangle")
    XCTAssertEqual(row("details", in: rows)?.title, "Details")
    XCTAssertEqual(row("details", in: rows)?.symbol, "info.circle")
    XCTAssertEqual(row("options", in: rows)?.title, "Options")
    XCTAssertEqual(row("options", in: rows)?.symbol, "gearshape")
    XCTAssertEqual(
      row("version.0", in: rows),
      MenuRow(id: "version.0", title: "Version 1.2.0 (7)", symbol: nil, kind: .info))
    XCTAssertEqual(row("check", in: rows)?.title, "Check for Updates…")
    XCTAssertEqual(row("about", in: rows)?.kind, .action(.about, enabled: true, key: ""))
    XCTAssertEqual(row("about", in: rows)?.title, "About TopNV")
    XCTAssertEqual(row("report", in: rows)?.title, "Report an Issue…")
    XCTAssertEqual(row("report", in: rows)?.kind, .action(.reportIssue, enabled: true, key: ""))
    XCTAssertEqual(
      row("quit", in: rows),
      MenuRow(
        id: "quit", title: "Quit TopNV", symbol: nil, kind: .action(.quit, enabled: true, key: "q"))
    )
    for id in ["check", "about", "report", "quit", "version.0"] {
      XCTAssertNil(row(id, in: rows)?.symbol, id)
    }

    let details = try XCTUnwrap(children("details", in: rows))
    XCTAssertEqual(
      details.map(\.title),
      ["Applies to: Built-in Display", "Permissions: None Required", "Requires macOS 14 or Later"])
    XCTAssertTrue(details.allSatisfy { $0.kind == .info && $0.symbol == nil })
    let allDisplays = try XCTUnwrap(
      children("details", in: self.rows(state(cornersOnAllDisplays: true))))
    XCTAssertEqual(allDisplays.first?.title, "Applies to: All Displays")

    let options = try XCTUnwrap(children("options", in: rows))
    XCTAssertEqual(row("cornersOnAllDisplays", in: options)?.title, "Corners on All Displays")
    XCTAssertEqual(row("cornersOnAllDisplays", in: options)?.symbol, "display.2")
    XCTAssertEqual(row("login", in: options)?.title, "Launch at Login")
    XCTAssertEqual(row("login", in: options)?.symbol, "power")
    XCTAssertEqual(row("automatic", in: options)?.title, "Automatic Updates")
    XCTAssertEqual(row("automatic", in: options)?.symbol, "arrow.triangle.2.circlepath")
    XCTAssertEqual(row("hide", in: options)?.title, "Hide Menu Bar Icon")
    XCTAssertEqual(row("hide", in: options)?.symbol, "menubar.rectangle")
    XCTAssertEqual(
      row("hide.caption.0", in: options),
      MenuRow(
        id: "hide.caption.0", title: "Open TopNV again to bring it back.", symbol: nil,
        kind: .info))
    XCTAssertEqual(row("options.separator", in: options)?.kind, .separator)
  }

  /// As in MonoPods, the TopNV group runs straight into Details and Options.
  func testNoSeparatorBetweenTheTopNVGroupAndDetails() throws {
    let rows = rows(state())
    let details = try XCTUnwrap(rows.firstIndex { $0.id == "details" })
    XCTAssertFalse(rows[..<details].contains { $0.kind == .separator })
  }

  func testStatusFollowsTheTwoSwitches() {
    for (hide, round) in [(true, true), (true, false), (false, true), (false, false)] {
      let status = MenuStatus(hideNotch: hide, roundCorners: round, localizer: english)
      XCTAssertEqual(
        rows(state(hideNotch: hide, roundCorners: round))[1],
        MenuRow(id: "status.0", title: status.title, symbol: status.symbol, kind: .info))
    }
  }

  // MARK: Switches and enabling

  func testSwitchesShowTheirStateAndEnabling() throws {
    for current in everyState {
      let rows = rows(current)
      XCTAssertEqual(
        row("hideNotch", in: rows)?.kind,
        .toggle(.hideNotch, isOn: current.hideNotch, enabled: true))
      XCTAssertEqual(
        row("roundCorners", in: rows)?.kind,
        .toggle(.roundCorners, isOn: current.roundCorners, enabled: true))
      XCTAssertEqual(row("details", in: rows)?.kind.isEnabledSubmenu, true)
      XCTAssertEqual(row("options", in: rows)?.kind.isEnabledSubmenu, true)
      let options = try XCTUnwrap(children("options", in: rows))
      XCTAssertEqual(
        row("cornersOnAllDisplays", in: options)?.kind,
        .toggle(
          .cornersOnAllDisplays, isOn: current.cornersOnAllDisplays,
          enabled: current.roundCorners))
      XCTAssertEqual(
        row("login", in: options)?.kind,
        .toggle(.launchAtLogin, isOn: current.launchAtLogin, enabled: true))
      XCTAssertEqual(
        row("hide", in: options)?.kind,
        .toggle(.hideMenuBarIcon, isOn: !current.menuVisible, enabled: true))
    }
  }

  /// Without an updater, MonoPods hides both update items instead of disabling them.
  func testUpdateItemsAppearOnlyWithAnUpdater() throws {
    for current in everyState {
      let rows = rows(current)
      let options = try XCTUnwrap(children("options", in: rows))
      if current.updatesAvailable {
        XCTAssertEqual(
          row("automatic", in: options)?.kind,
          .toggle(.automaticUpdates, isOn: current.automaticUpdates, enabled: true))
        XCTAssertEqual(
          row("check", in: rows)?.kind,
          .action(.checkForUpdates, enabled: current.canCheckForUpdates, key: ""))
      } else {
        XCTAssertNil(row("automatic", in: options))
        XCTAssertNil(row("check", in: rows))
      }
    }
  }

  // MARK: Login caption

  func testLoginCaptionIsAlwaysShown() throws {
    func caption(_ state: MenuState) throws -> [String] {
      try XCTUnwrap(children("options", in: rows(state)))
        .filter { $0.id.hasPrefix("login.caption.") }.map(\.title)
    }
    XCTAssertEqual(try caption(state()), ["Applies from the next login."])
    XCTAssertEqual(try caption(state(launchAtLogin: true)), ["Applies from the next login."])
    XCTAssertEqual(
      try caption(state(launchAtLogin: true, loginNeedsApproval: true)),
      ["Allow TopNV in System Settings > General >", "Login Items."])
    XCTAssertEqual(
      try caption(state(loginNeedsApproval: true, loginError: "Operation not permitted.")),
      ["Operation not permitted."])
    for blank in ["", "   ", "\n\t "] {
      XCTAssertEqual(try caption(state(loginError: blank)), ["Applies from the next login."])
      XCTAssertEqual(
        try caption(state(loginNeedsApproval: true, loginError: blank)),
        ["Allow TopNV in System Settings > General >", "Login Items."])
    }
  }

  func testALongLoginErrorIsSplitIntoShortRows() throws {
    let error = String(repeating: "The login item could not be registered. ", count: 4)
    let captions = try XCTUnwrap(children("options", in: rows(state(loginError: error))))
      .filter { $0.id.hasPrefix("login.caption.") }
    XCTAssertGreaterThan(captions.count, 1)
    XCTAssertEqual(captions.map(\.id), captions.indices.map { "login.caption.\($0)" })
    XCTAssertTrue(captions.allSatisfy { $0.title.count <= 44 && $0.kind == .info })
    XCTAssertTrue(captions.allSatisfy { $0.symbol == nil })
    XCTAssertEqual(
      captions.map(\.title).joined(separator: " "),
      error.split(whereSeparator: \.isWhitespace).joined(separator: " "))
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

  // MARK: Properties over every state

  func testPropertiesHoldInEveryState() {
    for current in everyState {
      let every = allRows(rows(current))
      let ids = every.map(\.id)
      XCTAssertEqual(Set(ids).count, ids.count, "\(current)")
      for row in every {
        if row.kind == .separator {
          XCTAssertTrue(row.title.isEmpty, row.id)
        } else {
          XCTAssertFalse(row.title.trimmingCharacters(in: .whitespaces).isEmpty, row.id)
        }
        XCTAssertFalse(row.id.lowercased().contains("radius"), row.id)
        XCTAssertFalse(row.title.lowercased().contains("radius"), row.title)
        if row.kind == .info {
          XCTAssertNil(row.kind.command, row.id)
        }
      }
    }
  }
}

extension MenuRow.Kind {
  fileprivate var isEnabledSubmenu: Bool? {
    if case .submenu(_, let enabled) = self { return enabled }
    return nil
  }

  /// The command a row runs when chosen; nil for rows that cannot be chosen.
  fileprivate var command: MenuCommand? {
    switch self {
    case .toggle(let command, _, _), .action(let command, _, _): return command
    case .header, .info, .submenu, .separator: return nil
    }
  }
}
