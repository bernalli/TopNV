/// Maps milliseconds since the first return signal to the production animation track.
public struct ReturnTiming {
  // Median of 16 layer-18 returns on November 19 (262...301 ms).
  public static let durationMS = 292.0
  private var endSignalMS: Double?

  public init() {}

  public func progress(at elapsed: Double) -> Double {
    // Keep one sample's worth of motion in reserve when the system runs late.
    let reserveMS = 1000.0 / 30
    func base(_ time: Double) -> Double {
      min(max(0, time), Self.durationMS - reserveMS) / Self.durationMS
    }
    guard let endSignalMS, elapsed >= endSignalMS else { return base(elapsed) }
    let from = base(endSignalMS)
    let tailMS = min(2 * reserveMS, (1 - from) * Self.durationMS)
    return from + (1 - from) * AnimationTiming.easeOut.progress(elapsed - endSignalMS, to: tailMS)
  }

  public mutating func surfaceEnded(at elapsed: Double) {
    if endSignalMS == nil { endSignalMS = max(0, elapsed) }
  }
}
