import AppKit
import TopNVCore

/// A temporary clipping parent lets the real corner drawing move inside its original window.
@MainActor
final class PreviewCorner {
  private let window: OverlayWindow
  private let drawing: NSView?
  private let wasLayerBacked: Bool
  private let top: Bool
  private let left: Bool

  init(corner: ScreenCorner, window: OverlayWindow) {
    self.window = window
    top = corner == .topLeft || corner == .topRight
    left = corner == .topLeft || corner == .bottomLeft
    drawing = window.contentView
    wasLayerBacked = drawing?.wantsLayer == true
    let wrapper = NSView(frame: CGRect(origin: .zero, size: window.frame.size))
    wrapper.wantsLayer = true
    wrapper.layer?.masksToBounds = true
    window.contentView = wrapper
    if let drawing {
      drawing.wantsLayer = true
      drawing.frame = wrapper.bounds
      wrapper.addSubview(drawing)
    }
  }

  func draw(_ variant: BarAnimation, at elapsed: Double) {
    guard let layer = drawing?.layer else { return }
    let corner = variant.corner(at: elapsed, top: top)
    let amount = corner.progress
    let topAtMaxY = layer.superlayer?.isGeometryFlipped != true
    let vertexX: CGFloat = left ? 0 : 1
    let vertexY: CGFloat = top == topAtMaxY ? 1 : 0
    let remainingWidth = (1 - amount) * layer.bounds.width
    let remainingHeight = (1 - amount) * layer.bounds.height
    let outwardY = (2 * vertexY - 1) * remainingHeight
    let anchorOffsetY = (vertexY - layer.anchorPoint.y) * remainingHeight
    var transform = CGAffineTransform.identity
    var opacity = 1.0
    switch corner.style {
    case .fade: opacity = amount
    case .slideFade:
      opacity = amount
      transform = .init(translationX: 0, y: outwardY)
    case .diagonal:
      let outwardX = (2 * vertexX - 1) * remainingWidth
      transform = .init(translationX: outwardX, y: outwardY)
    case .grow, .growFade:
      if corner.style == .growFade { opacity = amount }
      let anchorOffsetX = (vertexX - layer.anchorPoint.x) * remainingWidth
      transform = CGAffineTransform(translationX: anchorOffsetX, y: anchorOffsetY).scaledBy(x: amount, y: amount)
    case .unfold:
      transform = CGAffineTransform(translationX: 0, y: anchorOffsetY).scaledBy(x: 1, y: amount)
    }
    layer.opacity = amount == 0 ? 0 : Float(opacity)
    layer.setAffineTransform(transform)
  }

  func restore() {
    drawing?.layer?.setAffineTransform(.identity)
    drawing?.layer?.opacity = 1
    drawing?.removeFromSuperview()
    window.contentView = drawing
    drawing?.wantsLayer = wasLayerBacked
  }
}
