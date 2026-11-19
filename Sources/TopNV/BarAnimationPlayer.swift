import AppKit
import QuartzCore
import TopNVCore
import os

/// One display clock owns the pause, both band windows and all four corners. Cancellation removes
/// the presentation overrides synchronously, even in the initial pause or during a replay.
@MainActor
final class BarAnimationPlayer: NSObject {
  private static let logger = Logger(subsystem: "TopNV", category: "DesktopReturn")
  private var returnTiming: ReturnTiming?
  private var returnID: String?
  private var sawEnd = false
  private var lastTick: CFTimeInterval = 0
  private var link: CADisplayLink?
  private var surfaces: [PreviewBandSurface] = []
  private var variant = BarAnimation.curtain
  private var durationMS = 0.0
  private var start: CFTimeInterval = 0
  private var nextCheck: CFTimeInterval = 0
  private var currentTargets: (() -> [PreviewBandTarget])?
  /// Past the end by this much, the display link has stopped with its display.
  private static let overdueMS = 300.0

  func play(_ variant: BarAnimation, targets: @escaping () -> [PreviewBandTarget]) {
    cancel()
    let initial = targets()
    guard let screen = initial.first?.bar.screen else { return }
    begin(variant, initial: initial, screen: screen, pause: 0.6, validate: targets)
  }

  func enter(_ target: PreviewBandTarget, on screen: NSScreen, returnSignal: CFTimeInterval?, displayID: UInt32) {
    cancel()
    if let returnSignal {
      returnTiming = ReturnTiming()
      returnID = "\(displayID)/\(Int(returnSignal * 1000))"
      record("signalStart", at: returnSignal)
    }
    begin(.calm, initial: [target], screen: screen, pause: 0, validate: nil)
  }

  func includeKey(_ window: OverlayWindow, backdrop: CALayer) {
    guard let surface = surfaces.first else { return }
    transaction { surface.includeKey(window, backdrops: [backdrop]) }
  }

  private func begin(_ variant: BarAnimation, initial: [PreviewBandTarget], screen: NSScreen,
                     pause: Double, validate: (() -> [PreviewBandTarget])?) {
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
    self.variant = variant
    durationMS = variant.durationMS(rounded: initial.contains { !$0.corners.isEmpty })
    currentTargets = validate
    let now = CACurrentMediaTime()
    lastTick = now
    start = now + pause
    nextCheck = now + 0.1
    transaction {
      surfaces = initial.map { PreviewBandSurface(target: $0, variant: variant) }
      for surface in surfaces { surface.draw(variant, elapsed: pause > 0 ? -1 : 0) }
    }
    record("animationStart", at: now)
    let link = screen.displayLink(target: self, selector: #selector(tick))
    self.link = link
    link.add(to: .main, forMode: .common)
  }

  @objc private func tick() {
    let now = CACurrentMediaTime()
    lastTick = now
    let realMS = (now - start) * 1000
    let elapsed = returnTiming.map { $0.progress(at: realMS) * durationMS } ?? realMS
    if elapsed >= durationMS { finish("complete"); return }
    if let currentTargets, now >= nextCheck {
      nextCheck = now + 0.1
      // The keyed controller may have replaced a window or gated it during the pause.
      let targets = currentTargets()
      guard targets.count == surfaces.count,
            surfaces.allSatisfy({ surface in
              targets.contains { $0.bar === surface.target.bar && $0.keyed === surface.target.keyed }
            }) else { cancel(); return }
    }
    guard elapsed >= 0 else { return }
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { cancel(); return }
    transaction {
      for surface in surfaces { surface.draw(variant, elapsed: elapsed) }
    }
  }

  func surfaceEnded(at time: CFTimeInterval) {
    guard returnTiming != nil, !sawEnd else { return }
    sawEnd = true
    returnTiming?.surfaceEnded(at: (time - start) * 1000)
    record("signalEnd", at: time)
  }

  private func record(_ event: String, at time: CFTimeInterval) {
    guard let returnID else { return }
    let line = "return=\(returnID) \(event)MS=\(Int(time * 1000))"
    Self.logger.info("\(line, privacy: .public)")
  }

  func cancel() { finish("cancelled") }

  private func finish(_ reason: String) {
    if link != nil { record("animationEnd_\(reason)", at: CACurrentMediaTime()) }
    returnTiming = nil
    returnID = nil
    sawEnd = false
    link?.invalidate()
    link = nil
    currentTargets = nil
    guard !surfaces.isEmpty else { return }
    transaction {
      for surface in surfaces { surface.restore() }
      surfaces.removeAll()
    }
  }

  /// The display link is the only clock of an animation. A caller with a clock of its own ends
  /// an animation that the link left unfinished, so the band never stays partly open.
  func finishIfOverdue() {
    let now = CACurrentMediaTime()
    guard link != nil, (now - start) * 1000 >= durationMS,
          (now - lastTick) * 1000 >= Self.overdueMS else { return }
    finish("overdue")
  }

  func cancel(ifShowing bar: OverlayWindow) {
    if surfaces.contains(where: { $0.target.bar === bar }) { cancel() }
  }

  private func transaction(_ changes: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    changes()
    CATransaction.commit()
  }
}
