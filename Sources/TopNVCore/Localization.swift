import Foundation

/// Every visible text. The raw value is the lookup key and the English text; texts that name
/// the app take it as `%@`, so shared keys are the same in TopNV and MonoPods.
public enum TextKey: String, CaseIterable {
  // TopNV only.
  case hideNotch = "Hide Notch"
  case roundCorners = "Round Corners"
  case cornersOnAllDisplays = "Corners on All Displays"
  case notchHiddenCornersRounded = "Notch Hidden, Corners Rounded"
  case notchHidden = "Notch Hidden"
  case cornersRounded = "Corners Rounded"
  case inactive = "Inactive"
  case appliesToAllDisplays = "Applies To: All Displays"
  case appliesToBuiltInDisplay = "Applies To: Built-in Display"
  case permissionsNoneRequired = "Permissions: None Required"
  case requiresMacOS = "Requires macOS 14 or Later"
  case loginItemApproval = "Allow %@ in System Settings > General > Login Items."

  // Shared with MonoPods.
  case details = "Details"
  case options = "Options"
  case launchAtLogin = "Launch at Login"
  case hideMenuBarIcon = "Hide Menu Bar Icon"
  case hideMenuBarIconCaption = "Open %@ again to bring it back."
  case automaticUpdates = "Automatic Updates"
  case checkForUpdates = "Check for Updates…"
  case about = "About %@"
  case reportIssue = "Report an Issue…"
  case quit = "Quit %@"
  case version = "Version %@"
  case versionWithBuild = "Version %@ (%@)"
  case versionUnavailable = "Version Unavailable"
  case versionUnavailableWithBuild = "Version Unavailable (Build %@)"
  case viewOnGitHub = "View %@ on GitHub"
  case buyMeACoffee = "Buy Me a Coffee"
  case updateQuestionTitle = "Check for Updates Automatically?"
  case updateQuestionMessage =
    "%@ can check for new versions once a day. You can change this at any time in Options."
  case checkAutomatically = "Check Automatically"
  case dontCheck = "Don't Check"

  /// True when MonoPods shows the same text, so both apps must use the same translation.
  public var isShared: Bool {
    switch self {
    case .hideNotch, .roundCorners, .cornersOnAllDisplays, .notchHiddenCornersRounded,
      .notchHidden, .cornersRounded, .inactive,
      .appliesToAllDisplays, .appliesToBuiltInDisplay, .permissionsNoneRequired, .requiresMacOS,
      .loginItemApproval:
      return false
    default:
      return true
    }
  }
}

/// Looks texts up in `Localizable.strings` of a bundle; a missing table gives the English key.
public struct Localizer {
  public static let main = Localizer(bundle: .main)
  /// The app name is not translated.
  public static let appName = "TopNV"

  private let bundle: Bundle

  public init(bundle: Bundle) {
    self.bundle = bundle
  }

  public func callAsFunction(_ key: TextKey, _ arguments: CVarArg...) -> String {
    let format = bundle.localizedString(
      forKey: key.rawValue, value: key.rawValue, table: "Localizable")
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
  }
}
