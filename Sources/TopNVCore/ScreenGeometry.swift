import CoreGraphics

/// A corner of a screen, in AppKit coordinates (origin at the bottom-left, y grows upwards).
public enum ScreenCorner: String, CaseIterable, Sendable {
  case topLeft
  case topRight
  case bottomLeft
  case bottomRight
}

/// Pure geometry for the overlay windows. All inputs and outputs are in global AppKit
/// screen coordinates, so the functions can be tested without a window server.
public enum ScreenGeometry {
  /// The corner radius, in points. It is fixed: the app has no setting for it.
  public static let cornerRadius: CGFloat = 15

  /// A screen has a notch (camera housing) when the system reports a non-zero top safe-area inset.
  public static func isNotched(safeAreaTop: CGFloat) -> Bool {
    safeAreaTop > 0
  }

  /// Height of the menu-bar strip.
  ///
  /// Normally this is the gap between the top of the screen frame and the top of the visible
  /// frame. When the menu bar is auto-hidden that gap is zero, so the top safe-area inset is
  /// used instead, which still covers the notch.
  public static func menuBarHeight(
    frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat
  ) -> CGFloat {
    max(frame.maxY - visibleFrame.maxY, safeAreaTop, 0)
  }

  /// The radius actually used for a screen: never negative and never larger than half of the
  /// shorter screen side.
  public static func effectiveRadius(_ radius: CGFloat, frame: CGRect) -> CGFloat {
    guard radius.isFinite, radius > 0 else { return 0 }
    return min(radius, frame.width / 2, frame.height / 2)
  }

  /// Centre of the circle that is cut out of a corner square, in the square's local coordinates
  /// (origin at its bottom-left). It is the square's corner that points towards the screen centre.
  public static func arcCenter(for corner: ScreenCorner, side: CGFloat) -> CGPoint {
    switch corner {
    case .topLeft: return CGPoint(x: side, y: 0)
    case .topRight: return CGPoint(x: 0, y: 0)
    case .bottomLeft: return CGPoint(x: side, y: side)
    case .bottomRight: return CGPoint(x: 0, y: side)
    }
  }
}
