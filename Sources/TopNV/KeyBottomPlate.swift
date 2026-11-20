import AppKit
import TopNVCore

@MainActor
final class KeyBottomPlate {
  let layer = CALayer()
  private let original: BarPlate
  private let calibrated: BarPlate

  init(original: BarPlate, display: BarDisplay, keySize: CGSize) {
    self.original = original
    let menuHeight = display.frame.maxY - display.visibleFrame.maxY
    calibrated = BarGeometry.plate(keySize: keySize, menuHeight: menuHeight, scale: display.scale,
                                   margin: BarGeometry.calibratedPlateMargin)
  }

  func install(in root: CALayer, scale: CGFloat) {
    layer.frame = root.isGeometryFlipped ? original.flipped : original.unflipped
    layer.name = "Bottom plate"
    layer.contentsScale = scale
    layer.backgroundColor = NSColor.black.cgColor
    layer.isOpaque = true
    layer.zPosition = 1
    root.addSublayer(layer)
  }

  func apply(calibrated enabled: Bool) {
    guard let root = layer.superlayer else { return }
    let geometry = enabled ? calibrated : original
    layer.frame = root.isGeometryFlipped ? geometry.flipped : geometry.unflipped
  }
}
