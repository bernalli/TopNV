import AppKit
import QuartzCore
import TopNVCore
import os

@MainActor
protocol EntranceTiming: AnyObject {
  func start(_ entrance: BarEntrance, returnSignal: Double?, onFrame: @escaping (Double) -> Void,
             onFinish: @escaping () -> Void)
  func surfaceEnded(at time: Double)
  func finishIfOverdue()
  func cancel()
}

/// The presentation can finish before the sample that ends its return signal.
@MainActor
final class EntranceClock: NSObject, EntranceTiming {
  private static let logger = Logger(subsystem: "TopNV", category: "DesktopReturn")
  /// Past the end by this much, the display link has stopped with its display.
  private static let overdueMS = 300.0
  private let display: UInt32
  private var link: CADisplayLink?
  private var returnID: String?
  private var sawEnd = false
  private var timing: ReturnTiming?
  private var startTime = 0.0
  private var lastTick = 0.0
  private var durationMS = 0.0
  private var onFrame: ((Double) -> Void)?
  private var onFinish: (() -> Void)?

  init(display: UInt32) { self.display = display }

  func start(_ entrance: BarEntrance, returnSignal: Double?, onFrame: @escaping (Double) -> Void,
             onFinish: @escaping () -> Void) {
    cancel()
    guard let screen = NSScreen.screens.first(where: { $0.displayID == display }),
          !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { onFinish(); return }
    if let returnSignal {
      timing = ReturnTiming()
      returnID = "\(display)/\(Int(returnSignal * 1000))"
      record("signalStart", at: returnSignal)
    }
    self.onFrame = onFrame
    self.onFinish = onFinish
    let now = CACurrentMediaTime()
    durationMS = entrance.durationMS
    startTime = now - entrance.elapsedMS / 1000
    lastTick = now
    // The start plan already contains the first frame, including a preview's initial pause.
    record("animationStart", at: now)
    let link = screen.displayLink(target: self, selector: #selector(tick))
    self.link = link
    link.add(to: .main, forMode: .common)
  }

  @objc private func tick() {
    let now = CACurrentMediaTime()
    lastTick = now
    let realMS = (now - startTime) * 1000
    let elapsed = timing.map { $0.progress(at: realMS) * durationMS } ?? realMS
    if elapsed >= durationMS {
      let timedOut = timing?.usesTimeout == true
      finish(timedOut ? "signalTimeout" : "complete", awaitingEnd: timedOut)
    } else if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      cancel()
    } else if elapsed >= 0 {
      onFrame?(elapsed)
    }
  }

  func surfaceEnded(at time: Double) {
    guard returnID != nil, !sawEnd else { return }
    sawEnd = true
    timing?.surfaceEnded(at: (time - startTime) * 1000)
    record("signalEnd", at: time)
    if link == nil { returnID = nil }
  }

  func finishIfOverdue() {
    let now = CACurrentMediaTime()
    guard link != nil, (now - startTime) * 1000 >= durationMS, (now - lastTick) * 1000 >= Self.overdueMS else { return }
    finish("overdue", awaitingEnd: true)
  }

  func cancel() { finish("cancelled") }

  private func finish(_ reason: String, awaitingEnd: Bool = false) {
    if link != nil { record("animationEnd_\(reason)", at: CACurrentMediaTime()) }
    link?.invalidate()
    link = nil
    timing = nil
    if !awaitingEnd || sawEnd { returnID = nil }
    if returnID == nil { sawEnd = false }
    onFrame = nil
    let restore = onFinish
    onFinish = nil
    restore?()
  }

  private func record(_ event: String, at time: Double) {
    guard let returnID else { return }
    let line = "return=\(returnID) \(event)MS=\(Int(time * 1000))"
    Self.logger.info("\(line, privacy: .public)")
  }
}
