/// Luminance keys `clamp(0.5 + gain * (cutoff - Y))` on BT.709 luma for the keyed menu bar.
/// On a light wallpaper macOS draws two different backdrops under the menu bar, and no single
/// linear key fits both:
/// - normal: a light backdrop (Y about 0.87-0.90) under nearly black glyphs. A soft key, black
///   from Y 0.7325 and white up to Y 0.1075, keeps the antialiasing and the grey parts of the
///   icons (toggles, battery, volume). A steep key turns them black or makes them disappear.
/// - revealed: Show Desktop or a click on the wallpaper darkens the backdrop to Y about 0.32.
///   A steeper key, black from Y 0.2833, keeps that background black.
public enum LuminanceKey: Sendable {
  case normal, revealed

  public var gain: Float {
    switch self {
    case .normal: return 1.6
    case .revealed: return 6
    }
  }

  public var cutoff: Float {
    switch self {
    case .normal: return 0.42
    case .revealed: return 0.2
    }
  }

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

  /// The revealed desktop has its own key; everything else uses the normal one.
  public static func choose(desktopRevealed: Bool) -> LuminanceKey {
    desktopRevealed ? .revealed : .normal
  }
}
