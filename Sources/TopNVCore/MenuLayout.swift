import Foundation

/// What a selectable menu item does. The app target maps each command to an action.
public enum MenuCommand: String, CaseIterable, Sendable {
  case hideNotch
  case roundCorners
  case cornersOnAllDisplays
  case launchAtLogin
  case automaticUpdates
  case hideMenuBarIcon
  case checkForUpdates
  case about
  case reportIssue
  case quit
}

/// One native menu item. `id` is stable while the state changes, so an open menu keeps the same
/// item and only its title or state is updated.
public struct MenuRow: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    /// The native section title that names the group below it.
    case header
    /// Read-only text: not selectable and not highlighted under the pointer.
    case info
    case toggle(MenuCommand, isOn: Bool, enabled: Bool)
    case action(MenuCommand, enabled: Bool, key: String)
    case submenu([MenuRow], enabled: Bool)
    case separator
  }

  public let id: String
  public let title: String
  public let symbol: String?
  public let kind: Kind

  public init(id: String, title: String, symbol: String?, kind: Kind) {
    self.id = id
    self.title = title
    self.symbol = symbol
    self.kind = kind
  }
}

/// Everything the menu shows, read from the settings, the login item and the updater at one moment.
public struct MenuState: Equatable, Sendable {
  public var hideNotch: Bool
  public var roundCorners: Bool
  public var cornersOnAllDisplays: Bool
  public var launchAtLogin: Bool
  public var loginNeedsApproval: Bool
  /// The last registration error; blank text counts as no error.
  public var loginError: String?
  /// False without an updater: the update items are then not shown at all.
  public var updatesAvailable: Bool
  public var canCheckForUpdates: Bool
  public var automaticUpdates: Bool
  public var menuVisible: Bool
  public var versionTitle: String

  public init(
    hideNotch: Bool, roundCorners: Bool, cornersOnAllDisplays: Bool, launchAtLogin: Bool,
    loginNeedsApproval: Bool, loginError: String?, updatesAvailable: Bool,
    canCheckForUpdates: Bool, automaticUpdates: Bool, menuVisible: Bool, versionTitle: String
  ) {
    self.hideNotch = hideNotch
    self.roundCorners = roundCorners
    self.cornersOnAllDisplays = cornersOnAllDisplays
    self.launchAtLogin = launchAtLogin
    self.loginNeedsApproval = loginNeedsApproval
    self.loginError = loginError
    self.updatesAvailable = updatesAvailable
    self.canCheckForUpdates = canCheckForUpdates
    self.automaticUpdates = automaticUpdates
    self.menuVisible = menuVisible
    self.versionTitle = versionTitle
  }
}

/// The menu as a list of rows, without AppKit, so its content can be tested. The structure is
/// the one of MonoPods: header and status, the switches, Details and Options, a separator,
/// version and actions, a separator and Quit.
public enum MenuLayout {
  public static func rows(for state: MenuState, localizer: Localizer = .main) -> [MenuRow] {
    let appName = Localizer.appName
    let status = MenuStatus(
      hideNotch: state.hideNotch, roundCorners: state.roundCorners, localizer: localizer)
    var rows = [MenuRow(id: "topnv", title: appName, symbol: nil, kind: .header)]
    rows += info(status.title, id: "status", symbol: status.symbol)
    rows.append(
      MenuRow(
        id: "hideNotch", title: localizer(.hideNotch), symbol: "menubar.rectangle",
        kind: .toggle(.hideNotch, isOn: state.hideNotch, enabled: true)))
    rows.append(
      MenuRow(
        id: "roundCorners", title: localizer(.roundCorners), symbol: "rectangle",
        kind: .toggle(.roundCorners, isOn: state.roundCorners, enabled: true)))

    let scope: TextKey =
      state.cornersOnAllDisplays ? .appliesToAllDisplays : .appliesToBuiltInDisplay
    let details =
      info(localizer(scope), id: "display")
      + info(localizer(.permissionsNoneRequired), id: "permissions")
      + info(localizer(.requiresMacOS), id: "macOS")
    rows.append(
      MenuRow(
        id: "details", title: localizer(.details), symbol: "info.circle",
        kind: .submenu(details, enabled: true)))

    var options = [
      MenuRow(
        id: "cornersOnAllDisplays", title: localizer(.cornersOnAllDisplays), symbol: "display.2",
        kind: .toggle(
          .cornersOnAllDisplays, isOn: state.cornersOnAllDisplays, enabled: state.roundCorners)),
      MenuRow(
        id: "login", title: localizer(.launchAtLogin), symbol: "power",
        kind: .toggle(.launchAtLogin, isOn: state.launchAtLogin, enabled: true)),
    ]
    options += info(loginCaption(for: state, localizer: localizer), id: "login.caption")
    if state.updatesAvailable {
      options.append(
        MenuRow(
          id: "automatic", title: localizer(.automaticUpdates),
          symbol: "arrow.triangle.2.circlepath",
          kind: .toggle(.automaticUpdates, isOn: state.automaticUpdates, enabled: true)))
    }
    options.append(separator("options.separator"))
    options.append(
      MenuRow(
        id: "hide", title: localizer(.hideMenuBarIcon), symbol: "menubar.rectangle",
        kind: .toggle(.hideMenuBarIcon, isOn: !state.menuVisible, enabled: true)))
    options += info(localizer(.hideMenuBarIconCaption, appName), id: "hide.caption")
    rows.append(
      MenuRow(
        id: "options", title: localizer(.options), symbol: "gearshape",
        kind: .submenu(options, enabled: true)))

    rows.append(separator("separator.app"))
    rows += info(state.versionTitle, id: "version")
    if state.updatesAvailable {
      rows.append(
        MenuRow(
          id: "check", title: localizer(.checkForUpdates), symbol: nil,
          kind: .action(.checkForUpdates, enabled: state.canCheckForUpdates, key: "")))
    }
    rows.append(
      MenuRow(
        id: "about", title: localizer(.about, appName), symbol: nil,
        kind: .action(.about, enabled: true, key: "")))
    rows.append(
      MenuRow(
        id: "report", title: localizer(.reportIssue), symbol: nil,
        kind: .action(.reportIssue, enabled: true, key: "")))
    rows.append(separator("separator.quit"))
    rows.append(
      MenuRow(
        id: "quit", title: localizer(.quit, appName), symbol: nil,
        kind: .action(.quit, enabled: true, key: "q")))
    return rows
  }

  /// The row under Launch at Login is always there, as in MonoPods: the error, otherwise the
  /// approval request, otherwise when the setting takes effect.
  static func loginCaption(for state: MenuState, localizer: Localizer) -> String {
    if let error = state.loginError?.trimmingCharacters(in: .whitespacesAndNewlines),
      !error.isEmpty
    {
      return error
    }
    if state.loginNeedsApproval { return localizer(.loginItemApproval, Localizer.appName) }
    return localizer(.appliesFromNextLogin)
  }

  /// Free text as information rows of at most `MenuText.lines` width; only the first line carries
  /// the symbol. Blank text gives no rows.
  static func info(_ text: String, id: String, symbol: String? = nil) -> [MenuRow] {
    MenuText.lines(text).enumerated().map { line, title in
      MenuRow(id: "\(id).\(line)", title: title, symbol: line == 0 ? symbol : nil, kind: .info)
    }
  }

  private static func separator(_ id: String) -> MenuRow {
    MenuRow(id: id, title: "", symbol: nil, kind: .separator)
  }
}
