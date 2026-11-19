import AppKit
import TopNVCore
import os

/// A separate black surface above the keyed backdrop and below pop-up menus.
@MainActor
final class MenuEdgeCover {
  private static let logger = Logger(subsystem: "TopNV", category: "MenuEdge")
  private let trace = TestCopy.matches(Bundle.main.bundleIdentifier)
  private var loggedTarget: CGRect?
  private var loggedFrame: CGRect?
  private(set) var window: OverlayWindow?
  private let shape = CAShapeLayer()
  private var animation: (path: CGPath, bar: CGRect)?

  func update(frame: CGRect?, windows: [MenuBarEvidence.Window]?) {
    guard let frame else {
      if window?.isVisible == true { window?.orderOut(nil) }
      loggedFrame = nil
      return
    }
    if window == nil {
      let cover = OverlayWindow(frame: frame, level: .init(rawValue: MenuBarEvidence.overlayLevel + 1),
                                isOpaque: true, behavior: OverlayBehavior.bar)
      let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
      view.wantsLayer = true
      cover.contentView = view
      shape.fillColor = NSColor.black.cgColor
      view.layer?.addSublayer(shape)
      window = cover
    }
    guard let window else { return }
    if window.frame != frame || !window.isVisible {
      window.setFrame(frame, display: false)
      render()
      window.orderFrontRegardless()
    }
    // The on-screen list independently confirms the server's bounds after the window is ordered.
    if trace, animation == nil, let screen = window.screen,
       let listed = windows?.first(where: { $0.owner == .ownApp && $0.number == UInt32(window.windowNumber) }),
       listed.alpha == 1, loggedTarget != frame || loggedFrame != listed.bounds {
      let geometry = OverlayGeometry(screen: screen.frame, scale: screen.backingScaleFactor)
      let line = "topLeftPixels target=\(geometry.pixels(frame)) covered=\(geometry.pixels(listed.bounds)) "
        + "level=\(listed.layer) scale=\(geometry.scale)"
      Self.logger.info("\(line, privacy: .public)")
      loggedTarget = frame
      loggedFrame = listed.bounds
    }
  }

  func draw(_ path: CGPath, in bar: CGRect) {
    animation = (path, bar)
    render()
  }

  func finishAnimation() {
    animation = nil
    render()
  }

  private func render() {
    guard let window, let root = window.contentView?.layer else { return }
    let opaque = animation == nil
    if window.isOpaque != opaque {
      window.backgroundColor = opaque ? .black : .clear
      window.isOpaque = opaque
    }
    guard let animation else {
      shape.path = nil
      return
    }
    let edge = window.frame
    let menuBottom = animation.bar.maxY - edge.maxY
    let overlap = animation.bar.height - menuBottom
    let sourceTop: CGFloat
    let scale: CGFloat
    if overlap > 0 {
      // Keep the shared edge fixed while extending the path into the rest of the strip.
      sourceTop = menuBottom
      scale = max(1, edge.height / overlap)
    } else {
      // With no shared edge, let the strip grow over the last strip-height of the band.
      sourceTop = max(0, animation.bar.height - edge.height)
      scale = edge.height / (animation.bar.height - sourceTop)
    }
    let flipped = root.isGeometryFlipped
    let offset = sourceTop * scale
    var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: flipped ? scale : -scale,
                                      tx: animation.bar.minX - edge.minX,
                                      ty: flipped ? -offset : edge.height + offset)
    shape.frame = CGRect(origin: .zero, size: edge.size)
    shape.path = animation.path.copy(using: &transform)
  }

  func close() {
    window?.close()
    window = nil
  }
}
