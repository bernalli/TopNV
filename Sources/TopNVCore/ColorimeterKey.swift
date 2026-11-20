/// Transfer functions of the test lamp on encoded BT.709 luma.
public enum ColorimeterKey {
  public static let curve = KeyCurve(values: [-0.2343, 0.4979, 0.5459, 1.0979])
  public static let threshold = LuminanceKey.from(black: 230.0 / 255, white: 229.0 / 255)
  public static let pressedLevel: Float = 38.0 / 255
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
