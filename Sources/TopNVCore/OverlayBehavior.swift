import AppKit

/// How the overlay windows take part in Spaces and Mission Control.
public enum OverlayBehavior {
  /// A separate keyed window belongs to each visited Space and leaves Mission Control.
  public static let keyed: NSWindow.CollectionBehavior = [.transient, .ignoresCycle]
  /// Hides in Mission Control so the band does not show beneath the Spaces strip.
  public static let bar: NSWindow.CollectionBehavior = [
    .canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary,
  ]
  /// Hides in Mission Control: the top corners sit below the menu bar, over the Spaces bar.
  public static let corner: NSWindow.CollectionBehavior = [
    .canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary,
  ]
}
