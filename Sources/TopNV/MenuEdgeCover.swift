import AppKit
import TopNVCore

/// A separate black surface above the keyed backdrop and below pop-up menus.
@MainActor
final class MenuEdgeCover {
  private(set) var window: OverlayWindow?
  private let shape = CAShapeLayer()
  private var animation: (path: CGPath, bar: CGRect)?

  func update(frame: CGRect?) {
    guard let frame else {
      if window?.isVisible == true { window?.orderOut(nil) }
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
