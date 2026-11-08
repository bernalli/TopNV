import AppKit

/// How the overlay windows take part in Spaces and Mission Control.
public enum OverlayBehavior {
  /// Stays in place in Mission Control, like the desktop it covers.
  public static let bar: NSWindow.CollectionBehavior = [
    .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
  ]
  /// Hides in Mission Control: the top corners sit below the menu bar, over the Spaces bar.
  public static let corner: NSWindow.CollectionBehavior = [
    .canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary,
  ]
}
