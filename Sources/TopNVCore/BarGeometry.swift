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
  public static let separator: CGFloat = 1
  public static let edgeDepth: CGFloat = 2
  public static let plateGlyphMargin: CGFloat = 7.5

  public static func band(_ display: BarDisplay) -> CGRect? {
    ScreenGeometry.barRect(frame: display.frame, visibleFrame: display.visibleFrame, safeAreaTop: display.safeAreaTop)
  }

  public static func edge(menuBounds: CGRect?) -> CGRect? {
    guard let menu = menuBounds else { return nil }
    return CGRect(x: menu.minX, y: menu.minY - edgeDepth, width: menu.width, height: edgeDepth)
  }

  public static func plate(keySize: CGSize, menuHeight: CGFloat, scale: CGFloat) -> BarPlate {
    BarPlate(
      flipped: ScreenGeometry.keyedBottomMask(size: keySize, menuHeight: menuHeight, scale: scale, flipped: true),
      unflipped: ScreenGeometry.keyedBottomMask(size: keySize, menuHeight: menuHeight, scale: scale, flipped: false)
    )
  }

  public static func corners(display: CGRect, bandHeight: CGFloat?, rounded: Bool) -> [ScreenCorner: CGRect] {
    guard rounded else { return [:] }
    return ScreenGeometry.cornerRects(frame: display, radius: ScreenGeometry.cornerRadius, topInset: bandHeight ?? 0)
  }

  public static func blackBottom(band: PixelRect?, edge: PixelRect?) -> Int {
    [band?.bottom, edge?.bottom].compactMap { $0 }.max() ?? 0
  }

  public static func pixels(_ rect: CGRect?, on display: BarDisplay) -> PixelRect? {
    rect.flatMap { BarPixels.pixels($0, display: display.frame, scale: display.scale) }
  }
}
