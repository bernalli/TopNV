import CoreGraphics

/// The rounded corners step aside while the desktop of their display is revealed (Show Desktop,
/// a click on the wallpaper): macOS then draws the desktop as an inset tile with corners of its
/// own, which the fixed corners no longer match. They behave as in Mission Control, where they
/// disappear too. Missing or unknown evidence never hides them.
public enum CornerVisibility {
  public static func visible(_ evidence: MenuBarEvidence.Result?) -> Bool {
    guard let evidence, evidence.context != .unknown else { return true }
    return !evidence.desktopRevealed
  }

  /// The evidence of one display. Without a band (Hide Notch off, or a display without a notch)
  /// a one-point strip along the top edge stands in for it: only its validity matters here.
  public static func visible(frame: CGRect, visibleFrame: CGRect, bandFrame: CGRect?,
                             windows: [MenuBarEvidence.Window]?) -> Bool {
    guard let windows else { return true }
    let band = bandFrame ?? CGRect(x: frame.minX, y: frame.maxY - 1, width: frame.width, height: 1)
    return visible(MenuBarEvidence.evaluate(frame: frame, visibleFrame: visibleFrame, bandFrame: band,
                                            windows: windows))
  }
}
