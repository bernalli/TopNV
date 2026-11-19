import AppKit

/// All diagnostic rectangles share the display's top-left pixel origin.
struct OverlayGeometry {
  let screen: CGRect
  let scale: CGFloat

  func pixels(_ frame: CGRect?) -> String {
    guard let frame else { return "unavailable" }
    let rect = CGRect(x: (frame.minX - screen.minX) * scale, y: (screen.maxY - frame.maxY) * scale,
                      width: frame.width * scale, height: frame.height * scale)
    return NSStringFromRect(rect)
  }

  func pixels(layer: CALayer?, window: CGRect?) -> String {
    guard let layer, let window, let root = layer.superlayer else { return "unavailable" }
    var frame = layer.frame
    frame.origin.y = root.isGeometryFlipped ? window.maxY - frame.maxY : window.minY + frame.minY
    frame.origin.x += window.minX
    return pixels(frame)
  }
}
