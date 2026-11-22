import CoreGraphics

/// Two stationary, mirrored windows at the same distance from the notch.
public struct BandSlice {
  public let left: CGRect
  public let right: CGRect
  private let inner: CGFloat

  public func opacity(radius: CGFloat) -> CGFloat {
    min(1, max(0, (radius - inner) / right.width))
  }

  public static func pairs(in frame: CGRect) -> [BandSlice] {
    // 32 pairs give roughly one width step per refresh over a 292 ms return at 120 Hz.
    let count = 32
    let radius = frame.width / 2
    var inner: CGFloat = 0
    var result: [BandSlice] = []
    for index in 1...count {
      let outer = index == count ? radius : min(radius, (radius * CGFloat(index) / CGFloat(count)).rounded())
      guard outer > inner else { continue }
      let right = CGRect(x: frame.midX + inner, y: frame.minY, width: outer - inner, height: frame.height)
      let left = CGRect(x: frame.midX - outer, y: frame.minY, width: right.width, height: frame.height)
      result.append(BandSlice(left: left, right: right, inner: inner))
      inner = outer
    }
    return result
  }
}
