/// Raw values are the stable IDs of the reference animations. Swift rejects duplicate raw values.
public enum BarAnimation: String, CaseIterable, Sendable {
  case curtain = "astra-sipario"
  case ink = "astra-filo"
  case arrows = "astra-frecce"
  case breath = "astra-respiro"
  case calm = "fable-scorrimento-calmo"
  case stretch = "fable-notch-allungata"
  case blind = "fable-filo-tenda"
  case wave = "fable-onda-lenta"

  public var durationMS: Double {
    switch self {
    case .curtain, .stretch: 720
    case .ink: 880
    case .arrows: 620
    case .breath: 1120
    case .calm: 570
    case .blind: 840
    case .wave: 1150
    }
  }

  /// Three reference animations omit their corner track entirely when rounding is off.
  public func durationMS(rounded: Bool) -> Double {
    guard !rounded else { return durationMS }
    switch self {
    case .curtain: return 560
    case .ink: return 710
    case .arrows: return 490
    default: return durationMS
    }
  }

  public struct Frame {
    public var halfWidth: Double
    public var height: Double
    public var tip: Double = 0
    public var radius: Double = 0
    public var glyphOpacity: Double = 1
    public var glyphHalfWidth: Double
  }

  private static func calmProgress(at time: Double) -> Double {
    AnimationTiming.calm.progress(time, to: 410.4)
  }

  public func frame(at time: Double, width: Double, height: Double, notch: Double) -> Frame {
    let half = width / 2
    let radius = width * 0.011
    let start = max(0, notch / 2 - radius)
    var result = Frame(halfWidth: half, height: height, glyphHalfWidth: half)
    switch self {
    case .curtain:
      result.halfWidth = half * AnimationTiming.easeInOut.progress(time, to: 560)
    case .ink:
      result.halfWidth = half * AnimationTiming.easeInOut.progress(time, to: 426)
      result.height = height * (0.18 + 0.82 * AnimationTiming.easeOut.progress(time, from: 426, to: 710))
    case .arrows:
      result.halfWidth = half * AnimationTiming.arrow.progress(time, to: 420)
      result.tip = min(height * 1.5, notch / 3)
      result.glyphHalfWidth = half * AnimationTiming.easeOut.progress(time, from: 88.2, to: 490)
    case .breath:
      let first = AnimationTiming.easeOut.progress(time, to: 336)
      let second = AnimationTiming.easeInOut.progress(time, from: 432, to: 800)
      result.halfWidth = half * (0.54 * first + 0.46 * second)
      result.radius = min(999 * (1 - second), height / 2, result.halfWidth)
      result.glyphOpacity = AnimationTiming.linear.progress(time, from: 676.4, to: 890)
    case .calm:
      result.halfWidth = start + (half - start) * Self.calmProgress(at: time)
    case .stretch:
      result.halfWidth = start + (half + 1.5 * radius - start) * AnimationTiming.settle.progress(time, to: 504)
      result.radius = min(radius, height, result.halfWidth)
      result.glyphOpacity = AnimationTiming.easeOut.progress(time, from: 216, to: 540)
    case .blind:
      result.halfWidth = start + (half - start) * AnimationTiming.out.progress(time, to: 252)
      result.height = height * (0.2 + 0.8 * AnimationTiming.calm.progress(time, from: 310.8, to: 604.8))
    case .wave:
      let progress = AnimationTiming.slow.progress(time, to: 736)
      let bottom = max(start - height, 0)
      result.halfWidth = bottom + (half - bottom) * progress
      result.tip = min(start, height) + (height - min(start, height)) * progress
      result.glyphHalfWidth = start + (half - start) * AnimationTiming.slow.progress(time, from: 230, to: 966)
    }
    return result
  }

  public enum CornerStyle { case fade, slideFade, growFade, grow, unfold, diagonal }
  public struct Corner {
    public var style: CornerStyle
    public var progress: Double
  }

  public func corner(at time: Double, top: Bool) -> Corner {
    switch self {
    case .curtain: Corner(style: .fade, progress: AnimationTiming.easeOut.progress(time, from: 560, to: 720))
    case .ink: Corner(style: .slideFade, progress: AnimationTiming.easeOut.progress(time, from: 710, to: 880))
    case .arrows: Corner(style: .growFade, progress: AnimationTiming.easeOut.progress(time, from: 490, to: 620))
    case .breath: Corner(style: .fade, progress: AnimationTiming.linear.progress(
      time, from: top ? 890 : 1000, to: top ? 1000 : 1120))
    case .calm: Corner(style: .fade, progress: Self.calmProgress(at: time))
    case .stretch: Corner(style: .grow, progress: AnimationTiming.settle.progress(time, from: 324, to: 720))
    case .blind: Corner(style: .unfold, progress: AnimationTiming.out.progress(
      time, from: top ? 571.2 : 672, to: top ? 739.2 : 840))
    case .wave: Corner(style: .diagonal, progress: AnimationTiming.out.progress(time, from: 782, to: 1150))
    }
  }
}
