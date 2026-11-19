import Foundation

/// What a selectable menu item does. The app target maps each command to an action.
public enum MenuCommand: String, CaseIterable, Sendable {
  case previewCurtain = "astra-sipario"
  case previewInk = "astra-filo"
  case previewArrows = "astra-frecce"
  case previewBreath = "astra-respiro"
  case previewCalm = "fable-scorrimento-calmo"
  case previewStretch = "fable-notch-allungata"
  case previewBlind = "fable-filo-tenda"
  case previewWave = "fable-onda-lenta"
  case replayAnimation
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
  case relativeKey
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
  public var updates: UpdateItems
  public var lastAnimation: BarAnimation?
  public var isTestCopy: Bool

  public init(
    hideNotch: Bool, roundCorners: Bool, cornersOnAllDisplays: Bool, launchAtLogin: Bool,
    loginNeedsApproval: Bool, loginError: String?, updates: UpdateItems,
    isTestCopy: Bool = false
  ) {
    self.hideNotch = hideNotch
    self.roundCorners = roundCorners
    self.cornersOnAllDisplays = cornersOnAllDisplays
    self.launchAtLogin = launchAtLogin
    self.loginNeedsApproval = loginNeedsApproval
    self.loginError = loginError
    self.updates = updates
    self.isTestCopy = isTestCopy
  }
}

/// The menu as a list of rows, without AppKit, so its content can be tested: the header and the
/// two switches, Options, then About, Check for Updates…, Report an Issue… and Quit, with a
/// separator between the groups.
public enum MenuLayout {
  public static func rows(for state: MenuState, localizer: Localizer = .main) -> [MenuRow] {
    let appName = Localizer.appName
    var rows = [
      MenuRow(id: "topnv", title: appName, symbol: nil, kind: .header),
      MenuRow(
        id: "hideNotch", title: localizer(.hideNotch), symbol: "menubar.rectangle",
        kind: .toggle(.hideNotch, isOn: state.hideNotch, enabled: true)),
      MenuRow(
        id: "roundCorners", title: localizer(.roundCorners), symbol: "rectangle",
        kind: .toggle(.roundCorners, isOn: state.roundCorners, enabled: true)),
      separator("separator.options"),
      MenuRow(
        id: "options", title: localizer(.options), symbol: "gearshape",
        kind: .submenu(options(for: state, localizer: localizer), enabled: true))
    ]
    if state.isTestCopy {
      rows.append(animationPreview(for: state))
    }
    rows += [
      separator("separator.app"),
      MenuRow(
        id: "about", title: localizer(.about, appName), symbol: nil,
        kind: .action(.about, enabled: true, key: "")),
    ]
    // Before the first-launch answer the item is shown dimmed, so the menu keeps its shape.
    if state.updates != .hidden {
      rows.append(
        MenuRow(
          id: "check", title: localizer(.checkForUpdates), symbol: nil,
          kind: .action(.checkForUpdates, enabled: state.updates.canCheck, key: "")))
    }
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

  /// Round Corners on All Displays; Launch at Login and Check for Updates Automatically; Hide Menu
  /// Bar Icon, a command without a check mark, with the row that says how to get the icon back.
  static func options(for state: MenuState, localizer: Localizer) -> [MenuRow] {
    let loginTitle =
      state.loginNeedsApproval ? localizer(.launchAtLoginNeedsApproval) : localizer(.launchAtLogin)
    var options = [
      MenuRow(
        id: "cornersOnAllDisplays", title: localizer(.roundCornersOnAllDisplays),
        symbol: "display.2",
        kind: .toggle(
          .cornersOnAllDisplays, isOn: state.cornersOnAllDisplays, enabled: state.roundCorners)),
      separator("options.separator.login"),
      MenuRow(
        id: "login", title: loginTitle, symbol: "power",
        kind: .toggle(.launchAtLogin, isOn: state.launchAtLogin, enabled: true)),
    ]
    if let caption = loginCaption(for: state, localizer: localizer) {
      options += info(caption, id: "login.caption")
    }
    if state.updates != .hidden {
      options.append(
        MenuRow(
          id: "automatic", title: localizer(.checkForUpdatesAutomatically),
          symbol: "arrow.triangle.2.circlepath",
          kind: .toggle(
            .automaticUpdates, isOn: state.updates.checksAutomatically,
            enabled: state.updates.isReady)))
    }
    options.append(separator("options.separator"))
    options.append(
      MenuRow(
        id: "hide", title: localizer(.hideMenuBarIcon), symbol: "menubar.rectangle",
        kind: .action(.hideMenuBarIcon, enabled: true, key: "")))
    options += info(localizer(.hideMenuBarIconCaption, Localizer.appName), id: "hide.caption")
    return options
  }

  /// The grey row under Launch at Login, only when something needs the user: the registration
  /// error, otherwise the approval request. Nil while the login item works.
  static func loginCaption(for state: MenuState, localizer: Localizer) -> String? {
    if let error = state.loginError?.trimmingCharacters(in: .whitespacesAndNewlines),
      !error.isEmpty
    {
      return error
    }
    if state.loginNeedsApproval { return localizer(.loginItemApproval, Localizer.appName) }
    return nil
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
