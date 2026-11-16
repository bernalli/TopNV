import Foundation

/// Every visible text. The raw value is the lookup key and the English text; texts that name
/// the app take it as `%@`, so shared keys are the same in TopNV and MonoPods.
public enum TextKey: String, CaseIterable {
  // TopNV only.
  case hideNotch = "Hide Notch"
  case blackMenuBar = "Black Menu Bar on Light Wallpapers"
  case roundCorners = "Round Corners"
  case roundCornersOnAllDisplays = "Round Corners on All Displays"
  case launchAtLoginNeedsApproval = "Launch at Login (Requires Approval)"
  case loginItemApproval = "Allow %@ in System Settings > General > Login Items."

  // Shared with MonoPods.
  case options = "Options"
  case launchAtLogin = "Launch at Login"
  case hideMenuBarIcon = "Hide Menu Bar Icon"
  case hideMenuBarIconCaption = "Open %@ again to bring it back."
  case checkForUpdatesAutomatically = "Check for Updates Automatically"
  case checkForUpdates = "Check for Updates…"
  case about = "About %@"
  case reportIssue = "Report an Issue…"
  case quit = "Quit %@"
  case updateQuestionTitle = "Check for Updates Automatically?"
  case updateQuestionMessage =
    "%@ can check for new versions once a day. You can change this at any time in Options."
  case checkAutomatically = "Check Automatically"
  case dontCheck = "Don't Check"

  // English only: the About window reads no table.
  case version = "Version %@"
  case versionUnavailable = "Version Unavailable"

  /// Which tables carry a key.
  public enum Scope { case topNV, shared, englishOnly }

  public var scope: Scope {
    switch self {
    case .hideNotch, .blackMenuBar, .roundCorners, .roundCornersOnAllDisplays, .launchAtLoginNeedsApproval,
      .loginItemApproval:
      return .topNV
    case .options, .launchAtLogin, .hideMenuBarIcon, .hideMenuBarIconCaption,
      .checkForUpdatesAutomatically, .checkForUpdates, .about, .reportIssue, .quit,
      .updateQuestionTitle, .updateQuestionMessage, .checkAutomatically, .dontCheck:
      return .shared
    case .version, .versionUnavailable:
      return .englishOnly
    }
  }

  /// True when MonoPods shows the same text, so both apps must use the same translation.
  public var isShared: Bool { scope == .shared }

  /// False for the texts of the About window, which no table carries.
  public var isInTables: Bool { scope != .englishOnly }
}

/// Looks texts up in `Localizable.strings` of a bundle; a missing table gives the English key.
public struct Localizer {
  public static let main = Localizer(bundle: .main)
  /// The app name is not translated.
  public static let appName = "TopNV"

  /// Reads no table: the English text of every key, in every language (the About window).
  public static let english = Localizer(table: nil)

  /// Replaces `Bundle.main` for the lookups of this task, so a test can put a real table in
  /// effect for the default lookups. Other bundles and the English localizer are not affected.
  @TaskLocal static var bundleOverride: Bundle?

  private let bundle: Bundle?

  public init(bundle: Bundle) {
    self.bundle = bundle
  }

  private init(table bundle: Bundle?) {
    self.bundle = bundle
  }

  public func callAsFunction(_ key: TextKey, _ arguments: CVarArg...) -> String {
    let selected = bundle === Bundle.main ? (Self.bundleOverride ?? bundle) : bundle
    let format =
      selected?.localizedString(forKey: key.rawValue, value: key.rawValue, table: "Localizable")
      ?? key.rawValue
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
  }
}
