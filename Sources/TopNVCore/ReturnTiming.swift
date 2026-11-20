/// Maps milliseconds since the first return signal to the production animation track.
public struct ReturnTiming {
  // Median of 16 layer-18 returns on November 19 (262...301 ms).
  public static let durationMS = 292.0
  private static let sampleMS = 1000.0 / 30
  private static let reserveMS = 1000.0 / 60
  private static let timeoutMS = durationMS + sampleMS
  private var endSignalMS: Double?

  public init() {}

  public var usesTimeout: Bool { (endSignalMS ?? .infinity) > Self.timeoutMS }

  public func progress(at elapsed: Double) -> Double {
    // Hold a display frame of motion while waiting at most one extra window-list sample.
    let tailStart = min(endSignalMS ?? Self.timeoutMS, Self.timeoutMS)
    func base(_ time: Double) -> Double {
      min(max(0, time), Self.durationMS - Self.reserveMS) / Self.durationMS
    }
    guard elapsed >= tailStart else { return base(elapsed) }
    let from = base(tailStart)
    let tailMS = min(2 * Self.sampleMS, (1 - from) * Self.durationMS)
    return from + (1 - from) * AnimationTiming.easeOut.progress(elapsed - tailStart, to: tailMS)
  }

  public mutating func surfaceEnded(at elapsed: Double, receivedAt: Double? = nil) {
    guard endSignalMS == nil else { return }
    endSignalMS = max(0, max(elapsed, receivedAt ?? elapsed))
  }
}
