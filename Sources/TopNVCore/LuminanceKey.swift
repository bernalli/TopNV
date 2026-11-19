/// Luminance keys `clamp(0.5 + gain * (cutoff - Y))` on BT.709 luma for the keyed menu bar.
/// On a light wallpaper macOS draws two different backdrops under the menu bar, and no single
/// linear key fits both:
/// - normal: the menu bar backdrop under nearly black glyphs. Black from Y 0.3767 and white up
///   to Y 0.0433: the bar is black and the icons stay sharp. Calibrated by eye on the real menu
///   bar (18-11) with the calibration menu of a test copy. Screenshots do not contain the keyed
///   layer and do not show the backdrop of the render server, which is darker than they suggest:
///   a key measured on them (black from Y 0.7325) left the bar grey.
/// - revealed: Show Desktop or a click on the wallpaper darkens the backdrop to Y about 0.32.
///   A steeper key, black from Y 0.2833, keeps that background black.
/// A cubic Bezier on the output of the linear key, applied by the `luminanceCurveMap` filter
/// after the color matrix. `values` are its control values at input 0, 1/3, 2/3 and 1.
/// Both curves keep 0 at 0 and 1 at 1 and are never below the linear key: a pixel that the
/// matrix makes black stays black, and the dim parts between background and glyph get lighter.
public struct KeyCurve: Equatable, Sendable {
  public let values: [Double]

  /// `1 - (1 - t)^2`.
  public static let soft = KeyCurve(values: [0, 2.0 / 3.0, 1, 1])
  /// `1 - (1 - t)^3`.
  public static let strong = KeyCurve(values: [0, 1, 1, 1])

  private init(values: [Double]) {
    self.values = values
  }

  /// The arithmetic of the filter: the Bezier in Horner form, clamped to 0...1. The input is
  /// not clamped, because the render server may pass on the unclamped output of the matrix.
  public func output(_ input: Double) -> Double {
    let cubic = values[3] - 3 * values[2] + 3 * values[1] - values[0]
    let square = 3 * (values[0] - 2 * values[1] + values[2])
    let linear = 3 * (values[1] - values[0])
    return min(max(((cubic * input + square) * input + linear) * input + values[0], 0), 1)
  }
}

public enum LuminanceKey: Sendable {
  case normal, revealed

  public var gain: Float {
    switch self {
    case .normal: return 3
    case .revealed: return 6
    }
  }

  public var cutoff: Float {
    switch self {
    case .normal: return 0.21
    case .revealed: return 0.2
    }
  }

  /// The curve after the matrix. Nil is the linear key alone, as shipped in 1.2.5.
  public var curve: KeyCurve? { nil }

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

  /// The grey a luma becomes: the linear key, then the curve when there is one.
  public static func output(luma: Float, gain: Float, cutoff: Float, curve: KeyCurve?) -> Double {
    let linear = Double(0.5 + gain * (cutoff - luma))
    return curve?.output(linear) ?? min(max(linear, 0), 1)
  }

  /// The revealed desktop has its own key; everything else uses the normal one.
  public static func choose(desktopRevealed: Bool) -> LuminanceKey {
    desktopRevealed ? .revealed : .normal
  }
}
