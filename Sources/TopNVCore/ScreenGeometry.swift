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

  /// The rectangle of the black bar for a screen, or `nil` when the screen has no notch.
  public static func barRect(
    frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat
  ) -> CGRect? {
    guard isNotched(safeAreaTop: safeAreaTop) else { return nil }
    // The system surface ends above a one-point separator (rows 66 and 67 at 2x).
    let gap = frame.maxY - visibleFrame.maxY
    let height = min(frame.height, max(safeAreaTop, gap > 0 ? gap + 1 : 0))
    guard height > 0 else { return nil }
    return CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
  }

  /// Local frame of the opaque plate along the bottom edge of the keyed window.
  public static func keyedBottomMask(size: CGSize, menuHeight: CGFloat, scale: CGFloat, flipped: Bool) -> CGRect {
    let menu = menuHeight > 0 ? min(menuHeight, size.height) : size.height
    // On a 33-pt Retina menu the last glyph pixel is row 50. The gradient can
    // lighten row 51. Round towards the bottom so a glyph is never partly covered.
    let top = min(size.height, ceil(max(0, menu - 7.5) * scale) / scale)
    return CGRect(x: 0, y: flipped ? top : 0, width: size.width, height: size.height - top)
  }

  /// The radius actually used for a screen: never negative and never larger than half of the
  /// shorter screen side.
  public static func effectiveRadius(_ radius: CGFloat, frame: CGRect) -> CGFloat {
    guard radius.isFinite, radius > 0 else { return 0 }
    return min(radius, frame.width / 2, frame.height / 2)
  }

  /// The four square corner rectangles (side = radius) for a screen.
  /// Top corners start below `topInset`; negative or non-finite insets are treated as zero.
  /// Returns an empty dictionary when the radius or remaining height is zero (no windows needed).
  public static func cornerRects(
    frame: CGRect, radius: CGFloat, topInset: CGFloat = 0
  ) -> [ScreenCorner: CGRect] {
    let inset = topInset.isFinite ? max(topInset, 0) : 0
    var usableFrame = frame
    usableFrame.size.height = max(0, frame.height - inset)
    let side = effectiveRadius(radius, frame: usableFrame)
    guard side > 0 else { return [:] }
    return [
      .topLeft: CGRect(x: frame.minX, y: frame.maxY - inset - side, width: side, height: side),
      .topRight: CGRect(x: frame.maxX - side, y: frame.maxY - inset - side, width: side, height: side),
      .bottomLeft: CGRect(x: frame.minX, y: frame.minY, width: side, height: side),
      .bottomRight: CGRect(x: frame.maxX - side, y: frame.minY, width: side, height: side),
    ]
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
