import AppKit
import TopNVCore

@MainActor
final class KeyBottomPlate {
  let layer = CALayer()
  private var original: BarPlate
  private var calibrated: BarPlate
  private var menuDepth: CGFloat?

  init(original: BarPlate, calibrated: BarPlate, menuDepth: CGFloat?) {
    self.original = original
    self.calibrated = calibrated
    self.menuDepth = menuDepth
  }

  // The notch can hold the window's size constant when the menu depth changes.
  func update(_ key: BarKeyPlan, calibrated enabled: Bool) {
    guard key.confirmedMenuDepth != menuDepth, let original = key.plate,
          let calibrated = key.calibratedPlate else { return }
    menuDepth = key.confirmedMenuDepth
    self.original = original
    self.calibrated = calibrated
    apply(calibrated: enabled)
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
