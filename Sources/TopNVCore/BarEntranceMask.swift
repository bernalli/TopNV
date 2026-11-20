import CoreGraphics

/// A window-local mask measured from its top-left corner.
public enum BarMask: Equatable, Sendable {
  case none
  case rect(CGRect)
}

public enum BarEntranceMask {
  public static func band(elapsedMS: Double, bandSize: CGSize, notchWidth: CGFloat) -> BarMask {
    guard elapsedMS >= 0 else { return .rect(.zero) }
    let frame = BarAnimation.calm.frame(at: elapsedMS, width: bandSize.width, height: bandSize.height,
                                        notch: notchWidth)
    return .rect(CGRect(x: bandSize.width / 2 - frame.halfWidth, y: 0,
                        width: 2 * frame.halfWidth, height: frame.height))
  }

  public static func edge(band: BarMask, bandFrame: CGRect, edgeFrame: CGRect) -> BarMask {
    guard case .rect(let rect) = band else { return .none }
    guard !rect.isEmpty, bandFrame.height > 0, edgeFrame.height > 0 else { return .rect(.zero) }
    let menuBottom = bandFrame.maxY - edgeFrame.maxY
    let overlap = bandFrame.height - menuBottom
    let sourceTop: CGFloat
    let scale: CGFloat
    if overlap > 0 {
      sourceTop = menuBottom
      scale = max(1, edgeFrame.height / overlap)
    } else {
      sourceTop = max(0, bandFrame.height - edgeFrame.height)
      scale = edgeFrame.height / (bandFrame.height - sourceTop)
    }
    return .rect(CGRect(x: rect.minX + (bandFrame.minX - edgeFrame.minX), y: (rect.minY - sourceTop) * scale,
                        width: rect.width, height: rect.height * scale))
  }

  public static func keyBackdropExtent(band: BarMask, bandSize: CGSize) -> CGRect {
    let bounds = CGRect(origin: .zero, size: bandSize)
    guard case .rect(let rect) = band else { return bounds }
    let extent = bounds.intersection(rect)
    return extent.isEmpty ? .zero : extent
  }

  public static func cornerAlpha(elapsedMS: Double) -> Double {
    BarAnimation.calm.corner(at: elapsedMS, top: true).progress
  }

  public static func path(_ mask: BarMask, height: CGFloat, flipped: Bool) -> CGPath? {
    guard case .rect(var rect) = mask else { return nil }
    guard !rect.isEmpty else { return CGMutablePath() }
    if !flipped { rect.origin.y = height - rect.maxY }
    return CGPath(rect: rect, transform: nil)
  }
}
