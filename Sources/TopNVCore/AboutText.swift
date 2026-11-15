/// Visible texts of the About window. The window stays in English in every language, as
/// in MonoPods; the menu and its About item stay translated.
public enum AboutText {
  /// Reads no table, so the window title and the version row are English.
  public static let localizer = Localizer.english
  public static var windowTitle: String { localizer(.about, Localizer.appName) }
  /// Help tag and accessibility label of the GitHub mark.
  public static let gitHubHelp = "View \(Localizer.appName) on GitHub"
  public static let sponsor = "Buy Me a Coffee"
}
