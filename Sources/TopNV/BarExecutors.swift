import AppKit
import QuartzCore
import TopNVCore

typealias BarEntries = [BarRegistryID: BarRegistryEntry]

@MainActor
protocol BarPartExecuting {
  @discardableResult func apply(_ plan: BarPlan) -> BarEntries
  func closeAll()
}

@MainActor
protocol BarKeyExecuting: BarPartExecuting {
  func activeWindowIDs(display: UInt32) -> [Int]
  func closeChanged(frames: [UInt32: CGRect], enabled: Bool, scales: [UInt32: CGFloat]) -> Set<UInt32>
}

@MainActor
func applyBarPresentation(_ changes: () throws -> Void) rethrows {
  CATransaction.begin()
  defer { CATransaction.commit() }
  CATransaction.setDisableActions(true)
  try changes()
}

extension OverlayWindow {
  func registryEntry(on display: BarDisplay?, frame appliedFrame: CGRect? = nil,
                     mask: BarMask = .none) -> BarRegistryEntry {
    let pixels = display.flatMap { BarGeometry.pixels(appliedFrame ?? frame, on: $0) }
    var token = BarMaskToken.none
    if case let .rect(rect) = mask {
      let global = BarPixels.windowRect(layerFrame: rect, window: frame, flipped: true)
      token = display.flatMap { BarGeometry.pixels(global, on: $0) }.map(BarMaskToken.bounds) ?? .empty
    }
    let allSpaces = collectionBehavior.contains(.canJoinAllSpaces)
    return .init(pixels: pixels, alpha: allSpaces && !isVisible ? 0 : Double(alphaValue), level: level.rawValue,
                 window: windowNumber, mask: token, onActiveSpace: allSpaces || isOnActiveSpace)
  }
}

/// The band and edge each keep this view and its black shape for the life of the window.
@MainActor
final class BarStripView: NSView {
  private let shape = CAShapeLayer()

  private let color: NSColor

  init(in window: OverlayWindow, color: NSColor = .black) {
    self.color = color
    super.init(frame: CGRect(origin: .zero, size: window.frame.size))
    wantsLayer = true
    shape.fillColor = color.cgColor
    layer?.addSublayer(shape)
    window.contentView = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  func matches(_ mask: BarMask, in window: OverlayWindow) -> Bool {
    guard let root = layer, shape.superlayer === root else { return false }
    let bounds = CGRect(origin: .zero, size: window.frame.size)
    let path = BarEntranceMask.path(mask, height: bounds.height, flipped: root.isGeometryFlipped)
    let opaque = mask == .none
    return window.isOpaque == opaque && window.backgroundColor == (opaque ? color : .clear)
      && shape.frame == bounds && shape.path == path && shape.fillColor == color.cgColor
  }

  func apply(_ mask: BarMask, to window: OverlayWindow) {
    let opaque = mask == .none
    if window.isOpaque != opaque {
      window.isOpaque = opaque
      window.backgroundColor = opaque ? color : .clear
    }
    guard let root = layer else { return }
    let bounds = CGRect(origin: .zero, size: window.frame.size)
    if shape.frame != bounds { shape.frame = bounds }
    let path = BarEntranceMask.path(mask, height: bounds.height, flipped: root.isGeometryFlipped)
    if shape.path != path { shape.path = path }
  }
}
