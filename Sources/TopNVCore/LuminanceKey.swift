/// The normal menu bar key, calibrated by eye on the render server backdrop. Screenshots
/// omit the keyed layer and make the backdrop appear lighter than it is.
public struct LuminanceKey: Sendable {
  public static let normal = Self(gain: 3, cutoff: 0.21)
  public let gain: Float
  public let cutoff: Float

  /// Scale both endpoints by the same unfiltered background sample. Below one SDR
  /// code value the denominator is indistinguishable from black.
  public static func forBackdrop(backgroundLuma: Float?, relativeEnabled: Bool) -> Self {
    guard relativeEnabled, let backgroundLuma, backgroundLuma.isFinite,
          (1.0 / 255...1).contains(backgroundLuma) else { return .normal }
    let white = 0.20 * backgroundLuma
    let black = 0.93 * backgroundLuma
    return from(black: black, white: white)
  }

  static func from(black: Float, white: Float) -> Self {
    Self(gain: 1 / (black - white), cutoff: (white + black) / 2)
  }

  /// Luma at and above which the output is black.
  public var blackPoint: Float { cutoff + 0.5 / gain }
  /// Luma at and below which the output is white.
  public var whitePoint: Float { cutoff - 0.5 / gain }

  /// The 4x5 `colorMatrix` of the backdrop: the same luma row for red, green and blue, opaque alpha.
  public var matrix: [Float] {
    let row: [Float] = [-gain * 0.2126, -gain * 0.7152, -gain * 0.0722, 0, 0.5 + gain * cutoff]
    return row + row + row + [0, 0, 0, 0, 1]
  }
}
