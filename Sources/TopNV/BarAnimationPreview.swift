import AppKit
import QuartzCore
import TopNVCore

/// One display clock owns the pause, both band windows and all four corners. Cancellation removes
/// the presentation overrides synchronously, even in the initial pause or during a replay.
@MainActor
final class BarAnimationPreview: NSObject {
  private var link: CADisplayLink?
  private var surfaces: [PreviewBandSurface] = []
  private var variant = BarAnimation.curtain
  private var durationMS = 0.0
  private var start: CFTimeInterval = 0
  private var nextCheck: CFTimeInterval = 0
  private var currentTargets: (() -> [PreviewBandTarget])?

  func play(_ variant: BarAnimation, targets: @escaping () -> [PreviewBandTarget]) {
    cancel()
    let initial = targets()
    guard let screen = initial.first?.bar.screen else { return }
    self.variant = variant
    durationMS = variant.durationMS(rounded: initial.contains { !$0.corners.isEmpty })
    currentTargets = targets
    let now = CACurrentMediaTime()
    start = now + 0.6
    nextCheck = now + 0.1
    transaction {
      surfaces = initial.map { PreviewBandSurface(target: $0, variant: variant) }
      for surface in surfaces { surface.draw(variant, elapsed: -1) }
    }
    let link = screen.displayLink(target: self, selector: #selector(tick))
    self.link = link
    link.add(to: .main, forMode: .common)
  }

  @objc private func tick() {
    let now = CACurrentMediaTime()
    let elapsed = (now - start) * 1000
    if elapsed >= durationMS { cancel(); return }
    if now >= nextCheck {
      nextCheck = now + 0.1
      // The keyed controller may have replaced a window or gated it during the pause.
      guard let targets = currentTargets?(), targets.count == surfaces.count,
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

  func cancel() {
    link?.invalidate()
    link = nil
    currentTargets = nil
    guard !surfaces.isEmpty else { return }
    transaction {
      for surface in surfaces { surface.restore() }
      surfaces.removeAll()
    }
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
