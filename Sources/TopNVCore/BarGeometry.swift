import CoreGraphics

public struct BarDisplay: Equatable, Sendable {
  public let id: UInt32
  public let frame: CGRect
  public let visibleFrame: CGRect
  public let safeAreaTop: CGFloat
  public let scale: CGFloat
  public let notchWidth: CGFloat
  public let isBuiltin: Bool

  public init(id: UInt32, frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat,
              scale: CGFloat, notchWidth: CGFloat, isBuiltin: Bool) {
    self.id = id
    self.frame = frame
    self.visibleFrame = visibleFrame
    self.safeAreaTop = safeAreaTop
    self.scale = scale
    self.notchWidth = notchWidth
    self.isBuiltin = isBuiltin
  }
}

public struct BarPlate: Equatable, Sendable {
  public let flipped: CGRect
  public let unflipped: CGRect
}

public enum BarGeometry {
  public static let edgeDepth: CGFloat = 2
  // Cover the illuminated bottom rim while leaving the two-tone glyph edges visible.
  public static let calibratedPlateMargin: CGFloat = 4
  public static let plateGlyphMargin: CGFloat = 7.5

  /// The rectangle of the black bar for a screen, or `nil` when the screen has no notch.
  static func barRect(
    frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat
  ) -> CGRect? {
    guard ScreenGeometry.isNotched(safeAreaTop: safeAreaTop) else { return nil }
    // Use the reserved top when the menu window has not been measured.
    let gap = max(0, frame.maxY - visibleFrame.maxY)
    let height = min(frame.height, max(safeAreaTop, gap))
    guard height > 0 else { return nil }
    return topStrip(frame: frame, height: height)
  }

  static func topStrip(frame: CGRect, height: CGFloat) -> CGRect {
    CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
  }

  /// Local frame of the opaque plate along the bottom edge of the keyed window.
  static func keyedBottomMask(size: CGSize, menuHeight: CGFloat, scale: CGFloat, flipped: Bool,
                              margin: CGFloat = plateGlyphMargin) -> CGRect {
    let menu = menuHeight > 0 ? min(menuHeight, size.height) : size.height
    // On a 33-pt Retina menu the last glyph pixel is row 50. The gradient can
    // lighten row 51. Round towards the bottom so a glyph is never partly covered.
    let top = min(size.height, ceil(max(0, menu - margin) * scale) / scale)
    return CGRect(x: 0, y: flipped ? top : 0, width: size.width, height: size.height - top)
  }

  /// The four square corner rectangles (side = radius) for a screen.
  /// Top corners start below `topInset`; negative or non-finite insets are treated as zero.
  /// Returns an empty dictionary when the radius or remaining height is zero (no windows needed).
  static func cornerRects(
    frame: CGRect, radius: CGFloat, topInset: CGFloat = 0
  ) -> [ScreenCorner: CGRect] {
    let inset = topInset.isFinite ? max(topInset, 0) : 0
    var usableFrame = frame
    usableFrame.size.height = max(0, frame.height - inset)
    let side = ScreenGeometry.effectiveRadius(radius, frame: usableFrame)
    guard side > 0 else { return [:] }
    return [
      .topLeft: CGRect(x: frame.minX, y: frame.maxY - inset - side, width: side, height: side),
      .topRight: CGRect(x: frame.maxX - side, y: frame.maxY - inset - side, width: side, height: side),
      .bottomLeft: CGRect(x: frame.minX, y: frame.minY, width: side, height: side),
      .bottomRight: CGRect(x: frame.maxX - side, y: frame.minY, width: side, height: side)
    ]
  }

  public static func band(_ display: BarDisplay) -> CGRect? {
    barRect(frame: display.frame, visibleFrame: display.visibleFrame, safeAreaTop: display.safeAreaTop)
  }

  public static func edge(menuBounds: CGRect?, band: CGRect?) -> CGRect? {
    guard let menu = menuBounds, let band else { return nil }
    let room = menu.minY - band.minY
    guard room.isFinite, room > 0, menu.minX.isFinite, menu.width.isFinite else { return nil }
    let height = min(edgeDepth, room)
    return CGRect(x: menu.minX, y: menu.minY - height, width: menu.width, height: height)
  }

  public static func plate(keySize: CGSize, menuHeight: CGFloat, scale: CGFloat,
                           margin: CGFloat = plateGlyphMargin) -> BarPlate {
    BarPlate(
      flipped: keyedBottomMask(size: keySize, menuHeight: menuHeight, scale: scale, flipped: true, margin: margin),
      unflipped: keyedBottomMask(size: keySize, menuHeight: menuHeight, scale: scale, flipped: false, margin: margin)
    )
  }

  public static func corners(display: CGRect, bandHeight: CGFloat?, rounded: Bool) -> [ScreenCorner: CGRect] {
    guard rounded else { return [:] }
    return cornerRects(frame: display, radius: ScreenGeometry.cornerRadius, topInset: bandHeight ?? 0)
  }

  public static func blackBottom(band: PixelRect?, edge: PixelRect?) -> Int {
    [band?.bottom, edge?.bottom].compactMap { $0 }.max() ?? 0
  }

  public static func pixels(_ rect: CGRect?, on display: BarDisplay) -> PixelRect? {
    rect.flatMap { BarPixels.pixels($0, display: display.frame, scale: display.scale) }
  }
}
