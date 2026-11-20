/// Transfer functions of the illuminated menu bar on encoded BT.709 luma.
public enum ColorimeterKey {
  private static let fullScale: Float = 255
  public static let glyph = LuminanceKey.from(black: 263.67 / fullScale, white: -0.04 / fullScale)
  public static let curve = KeyCurve(values: [-0.2343, 0.4979, 0.5459, 1.0979])
  public static let threshold = LuminanceKey.from(black: 230.0 / fullScale, white: 229.0 / fullScale)
  public static let pressedLevel: Float = 38.0 / fullScale
}

public struct KeyCurve: Sendable {
  public let values: [Double]
  fileprivate init(values: [Double]) { self.values = values }

  public func output(_ input: Double) -> Double {
    let cubic = values[3] - 3 * values[2] + 3 * values[1] - values[0]
    let square = 3 * (values[0] - 2 * values[1] + values[2])
    let linear = 3 * (values[1] - values[0])
    return min(max(((cubic * input + square) * input + linear) * input + values[0], 0), 1)
  }
}
