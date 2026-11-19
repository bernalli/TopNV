import AppKit
import QuartzCore
import TopNVCore

extension NSScreen {
  var previewNotchWidth: CGFloat {
    guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return 0 }
    return max(0, right.minX - left.maxX)
  }
}

/// Surfaces owned by the normal overlay controllers. Window visibility stays under their control.
@MainActor
struct PreviewBandTarget {
  let notchWidth: CGFloat
  let bar: OverlayWindow
  let keyed: OverlayWindow?
  let backdrops: [CALayer]
  let corners: [ScreenCorner: OverlayWindow]
}

@MainActor
final class PreviewBandSurface {
  let target: PreviewBandTarget
  private let originalView: NSView?
  private let originalColor: NSColor
  private let originalOpaque: Bool
  private let originalMask: CALayer?
  private let backdropFrames: [CGRect]
  private let band = CAShapeLayer()
  private let keyedMask = CAShapeLayer()
  private let coverMask = CAShapeLayer()
  private let leftCover = CALayer()
  private let rightCover = CALayer()
  private let cover: OverlayWindow?
  private let corners: [PreviewCorner]

  init(target: PreviewBandTarget, variant: BarAnimation) {
    self.target = target
    let bar = target.bar
    let bounds = CGRect(origin: .zero, size: bar.frame.size)
    originalView = bar.contentView
    originalColor = bar.backgroundColor
    originalOpaque = bar.isOpaque
    originalMask = target.keyed?.contentView?.layer?.mask
    backdropFrames = target.backdrops.map(\.frame)
    corners = target.corners.map { PreviewCorner(corner: $0.key, window: $0.value) }
    let view = NSView(frame: bounds)
    view.wantsLayer = true
    band.frame = bounds
    band.contentsScale = bar.backingScaleFactor
    view.layer?.addSublayer(band)
    bar.isOpaque = false
    bar.backgroundColor = .clear
    bar.contentView = view
    keyedMask.frame = bounds
    keyedMask.contentsScale = bar.backingScaleFactor
    target.keyed?.contentView?.layer?.mask = keyedMask

    // Black above the real glyphs can fade or retreat without moving or capturing them.
    switch variant {
    case .arrows, .breath, .stretch, .wave:
      let window = OverlayWindow(frame: bar.frame, level: .init(rawValue: MenuBarEvidence.overlayLevel + 1),
                                 isOpaque: false, behavior: OverlayBehavior.keyed)
      let host = NSView(frame: bounds)
      host.wantsLayer = true
      window.contentView = host
      coverMask.frame = bounds
      coverMask.contentsScale = bar.backingScaleFactor
      host.layer?.mask = coverMask
      for layer in [leftCover, rightCover] {
        layer.backgroundColor = NSColor.black.cgColor
        host.layer?.addSublayer(layer)
      }
      window.orderFrontRegardless()
      cover = window
    default:
      cover = nil
    }
  }

  func draw(_ variant: BarAnimation, elapsed: Double) {
    let size = band.bounds.size
    let frame = variant.frame(at: elapsed, width: size.width, height: size.height, notch: target.notchWidth)
    let hidden = elapsed < 0
    let path = hidden ? CGMutablePath() : Self.path(variant, frame, width: size.width)
    band.path = oriented(path, in: band.superlayer)
    keyedMask.path = oriented(path, in: target.keyed?.contentView?.layer)
    coverMask.path = oriented(path, in: cover?.contentView?.layer)

    // Also bound the actual private sampling surfaces. Rectangular wipes therefore do not rely
    // on the compositor applying an ancestor mask to a window-server-aware backdrop.
    let extent = hidden ? CGRect.zero : path.boundingBoxOfPath.intersection(band.bounds)
    for layer in target.backdrops {
      let flipped = layer.superlayer?.isGeometryFlipped == true
      layer.frame = extent.isNull || extent.isEmpty ? .zero : CGRect(
        x: extent.minX, y: flipped ? extent.minY : size.height - extent.maxY,
        width: extent.width, height: extent.height)
    }
    let side = max(0, size.width / 2 - frame.glyphHalfWidth)
    let fading = variant == .stretch || variant == .breath
    leftCover.frame = CGRect(x: 0, y: 0, width: fading ? size.width : side, height: size.height)
    leftCover.opacity = fading ? Float(1 - frame.glyphOpacity) : 1
    rightCover.frame = CGRect(x: size.width - side, y: 0, width: side, height: size.height)
    for corner in corners { corner.draw(variant, at: elapsed) }
  }

  private func oriented(_ path: CGPath, in root: CALayer?) -> CGPath {
    guard root?.isGeometryFlipped != true else { return path }
    var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: band.bounds.height)
    return path.copy(using: &flip) ?? path
  }

  private static func path(_ variant: BarAnimation, _ frame: BarAnimation.Frame, width: CGFloat) -> CGPath {
    let left = width / 2 - frame.halfWidth
    let right = width / 2 + frame.halfWidth
    let height = frame.height
    let rect = CGRect(x: left, y: 0, width: right - left, height: height)
    let radius = frame.radius
    let path = CGMutablePath()
    switch variant {
    case .arrows:
      path.addLines(between: [CGPoint(x: left, y: 0), CGPoint(x: right, y: 0),
                              CGPoint(x: right + frame.tip, y: height / 2), CGPoint(x: right, y: height),
                              CGPoint(x: left, y: height), CGPoint(x: left - frame.tip, y: height / 2)])
    case .wave:
      path.addLines(between: [CGPoint(x: left - frame.tip, y: 0), CGPoint(x: right + frame.tip, y: 0),
                              CGPoint(x: right, y: height), CGPoint(x: left, y: height)])
    case .stretch where radius > 0:
      path.move(to: CGPoint(x: left, y: 0))
      path.addLine(to: CGPoint(x: right, y: 0))
      path.addArc(tangent1End: CGPoint(x: right, y: height), tangent2End: CGPoint(x: right - radius, y: height),
                  radius: radius)
      path.addArc(tangent1End: CGPoint(x: left, y: height), tangent2End: CGPoint(x: left, y: 0), radius: radius)
    default:
      return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    path.closeSubpath()
    return path
  }

  func restore() {
    cover?.orderOut(nil)
    cover?.close()
    target.keyed?.contentView?.layer?.mask = originalMask
    for (layer, frame) in zip(target.backdrops, backdropFrames) { layer.frame = frame }
    target.bar.contentView = originalView
    target.bar.backgroundColor = originalColor
    target.bar.isOpaque = originalOpaque
    for corner in corners { corner.restore() }
  }
}
