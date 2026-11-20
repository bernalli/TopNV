import AppKit
import TopNVCore

@MainActor
final class KeyBottomPlate {
  let layer = CALayer()
  private let original: BarPlate
  private let menuHeight: CGFloat
  private var applied: MenuCommand?

  init(original: BarPlate, display: BarDisplay) {
    self.original = original
    menuHeight = display.frame.maxY - display.visibleFrame.maxY
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

  func apply(_ preset: LampPlatePreset?, log: (String) -> Void) {
    guard applied != preset?.command, let root = layer.superlayer else { return }
    applied = preset?.command
    let geometry = preset.map {
      BarGeometry.plate(keySize: root.bounds.size, menuHeight: menuHeight,
                        scale: layer.contentsScale, margin: $0.margin)
    } ?? original
    layer.frame = root.isGeometryFlipped ? geometry.flipped : geometry.unflipped
    if let preset {
      let row = preset.margin == nil ? "none" : String(Int((geometry.flipped.minY * layer.contentsScale).rounded()))
      log("LampPlate voce=\(preset.number) margin=\(preset.marginText) px=\(row)")
    }
  }
}
