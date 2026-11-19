import CoreGraphics

public struct PixelRect: Equatable, Hashable, Sendable, CustomStringConvertible {
  public let x, y, width, height: Int

  public init(x originX: Int, y originY: Int, width: Int, height: Int) {
    self.x = originX
    self.y = originY
    self.width = width
    self.height = height
  }

  public var bottom: Int { y + height }
  public var description: String { "\(x),\(y),\(width),\(height)" }
}

public enum BarPixels {
  public static func pixels(_ rect: CGRect, display: CGRect, scale: CGFloat) -> PixelRect? {
    guard valid(rect), valid(display), scale.isFinite, scale > 0 else { return nil }
    let epsilon: CGFloat = 1e-6
    guard let left = Int(exactly: floor((rect.minX - display.minX) * scale + epsilon)),
          let top = Int(exactly: floor((display.maxY - rect.maxY) * scale + epsilon)),
          let right = Int(exactly: ceil((rect.maxX - display.minX) * scale - epsilon)),
          let bottom = Int(exactly: ceil((display.maxY - rect.minY) * scale - epsilon)) else { return nil }
    let (width, widthOverflow) = right.subtractingReportingOverflow(left)
    let (height, heightOverflow) = bottom.subtractingReportingOverflow(top)
    guard !widthOverflow, !heightOverflow else { return nil }
    return PixelRect(x: left, y: top, width: width, height: height)
  }

  private static func valid(_ rect: CGRect) -> Bool {
    !rect.isNull && !rect.isInfinite && rect.size.width > 0 && rect.size.height > 0
      && rect.minX.isFinite && rect.minY.isFinite && rect.maxX.isFinite && rect.maxY.isFinite
  }

  public static func windowRect(layerFrame: CGRect, window: CGRect, flipped: Bool) -> CGRect {
    CGRect(origin: CGPoint(x: window.minX + layerFrame.minX,
                           y: flipped ? window.maxY - layerFrame.maxY : window.minY + layerFrame.minY),
           size: layerFrame.size)
  }
}
