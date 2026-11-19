/// The normal menu bar key, calibrated by eye on the render server backdrop. Screenshots
/// omit the keyed layer and make the backdrop appear lighter than it is.
public struct LuminanceKey: Sendable {
  public static let normal = Self(gain: 3, cutoff: 0.21)
  public let gain: Float
  public let cutoff: Float

  /// Luma at and above which the output is black.
  public var blackPoint: Float { cutoff + 0.5 / gain }
  /// Luma at and below which the output is white.
  public var whitePoint: Float { cutoff - 0.5 / gain }

  /// The 4x5 `colorMatrix` of the backdrop: the same luma row for red, green and blue, opaque alpha.
  public var matrix: [Float] { Self.matrix(gain: gain, cutoff: cutoff) }

  /// The matrix of any linear key, also of a calibration candidate.
  public static func matrix(gain: Float, cutoff: Float) -> [Float] {
    let row: [Float] = [-gain * 0.2126, -gain * 0.7152, -gain * 0.0722, 0, 0.5 + gain * cutoff]
    return row + row + row + [0, 0, 0, 0, 1]
  }
}
