import Foundation
import QuartzCore
import TopNVCore

struct ProbeClock {
  var now: () -> TimeInterval = CACurrentMediaTime
  var schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Timer = { interval, action in
    let timer = Timer(fire: Date(timeIntervalSinceNow: interval), interval: interval, repeats: true) { _ in
      MainActor.assumeIsolated { action() }
    }
    RunLoop.main.add(timer, forMode: .common)
    return timer
  }
}

/// One observation window per backdrop. A successful request and a returned value are independent.
struct BackdropProbe {
  static let interval: TimeInterval = 1
  let display: UInt32
  private(set) var lastCallback: TimeInterval?
  private var started: TimeInterval?
  private var forced = false
  private var reading: Float?

  init(display: UInt32) { self.display = display }

  mutating func begin(at time: TimeInterval, forced: Bool) {
    started = time
    self.forced = forced
    reading = nil
  }

  mutating func receive(_ luma: Float, at time: TimeInterval) {
    lastCallback = time
    if forced, let started, time >= started, time <= started + Self.interval {
      reading = luma.isFinite ? luma : nil
    }
  }

  func line(at time: TimeInterval, key: LuminanceKey, fixed: Bool = false) -> String {
    let luma = reading.map { Self.format(Double($0)) } ?? "none"
    let age = lastCallback.map { Self.format(max(0, time - $0)) } ?? "none"
    let mode: String
    if fixed {
      mode = "fixed"
    } else {
      mode = key.matrix == LuminanceKey.normal.matrix ? "normal" : "relative"
    }
    return "Probe display=\(display) luma=\(luma) forced=\(forced) lastCallbackAge=\(age) "
      + "key=\(mode) white=\(Self.format(Double(key.whitePoint))) black=\(Self.format(Double(key.blackPoint)))"
  }

  static func format(_ value: Double) -> String { String(format: "%.3f", value) }
}
