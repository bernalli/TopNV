import AppKit
import QuartzCore
import TopNVCore
import os

@MainActor
final class BarRegistryProbe {
  private let logger = Logger(subsystem: "TopNV", category: "BarSurface")
  private var registry: BarRegistry

  init(testCopy: Bool) {
    registry = BarRegistry(testCopy: testCopy)
  }

  @discardableResult
  func record(_ snapshot: BarRegistrySnapshot, ownWindows: [MenuBarEvidence.Window]?) -> [String] {
    let lines = registry.record(snapshot, ownWindows: ownWindows)
    for line in lines { logger.info("\(line, privacy: .public)") }
    return lines
  }

  struct KeyWindow {
    let display: UInt32
    let number: Int
    let frame: CGRect
    let alpha: Double
    let level: Int
    let onActiveSpace: Bool
    let plate: CGRect?
    let mask: CGRect?

    @MainActor init(display: UInt32, window: OverlayWindow) {
      self.display = display
      number = window.windowNumber
      frame = window.frame
      alpha = Double(window.alphaValue)
      level = window.level.rawValue
      onActiveSpace = window.isOnActiveSpace
      let root = window.contentView?.layer
      let flipped = root?.isGeometryFlipped == true
      plate = root?.sublayers?.first { $0.name == "Bottom plate" }.map {
        BarPixels.windowRect(layerFrame: $0.frame, window: window.frame, flipped: flipped)
      }
      mask = BarRegistryProbe.maskBounds(root?.mask as? CAShapeLayer, window: window.frame, flipped: flipped)
    }
  }

  // A missing shape has no mask. A shape with no filled extent clips everything.
  private static func maskBounds(_ shape: CAShapeLayer?, window: CGRect, flipped: Bool) -> CGRect? {
    guard let shape else { return nil }
    guard let path = shape.path, !path.isEmpty else { return .null }
    return BarPixels.windowRect(layerFrame: path.boundingBoxOfPath, window: window, flipped: flipped)
  }

  private static func maskToken(_ bounds: CGRect?, on screen: NSScreen) -> BarMaskToken {
    guard let bounds else { return .none }
    guard let pixels = BarPixels.pixels(bounds, display: screen.frame, scale: screen.backingScaleFactor)
    else { return .empty }
    return .bounds(pixels)
  }

  private static func entry(_ window: OverlayWindow, on screen: NSScreen, readsShape: Bool) -> BarRegistryEntry {
    var bounds: CGRect?
    if readsShape && !window.isOpaque {
      let root = window.contentView?.layer
      let shape = root?.sublayers?.first { $0 is CAShapeLayer } as? CAShapeLayer
      bounds = maskBounds(shape, window: window.frame, flipped: root?.isGeometryFlipped == true)
    }
    return .init(pixels: BarPixels.pixels(window.frame, display: screen.frame, scale: screen.backingScaleFactor),
                 alpha: window.isVisible ? Double(window.alphaValue) : 0, level: window.level.rawValue,
                 window: window.windowNumber, mask: maskToken(bounds, on: screen), onActiveSpace: true)
  }

  static func snapshot(screens: [NSScreen], bars: [UInt32: BarWindow], corners: [String: CornerWindow],
                       keys: [KeyWindow], evidence: [UInt32: MenuBarEvidence.Result]) -> BarRegistrySnapshot {
    var entries: [BarRegistryID: BarRegistryEntry] = [:]
    var displays: [UInt32: BarRegistryDisplay] = [:]
    for screen in screens {
      guard let display = screen.displayID else { continue }
      let bar = bars[display]
      let band = bar.map { entry($0, on: screen, readsShape: true) }
      let edge = bar?.menuEdge.window.map { entry($0, on: screen, readsShape: true) }
      entries[.init(display: display, part: .band)] = band
      entries[.init(display: display, part: .edge)] = edge
      for corner in ScreenCorner.allCases {
        if let window = corners["\(display).\(corner.rawValue)"] {
          entries[.init(display: display, part: .corner(corner))] = entry(window, on: screen, readsShape: false)
        }
      }
      let scale = screen.backingScaleFactor
      for key in keys where key.display == display {
        let keyID = BarRegistryID(display: display, part: .key, keyWindow: key.number)
        entries[keyID] = .init(pixels: BarPixels.pixels(key.frame, display: screen.frame, scale: scale),
                               alpha: key.alpha, level: key.level, window: key.number,
                               mask: maskToken(key.mask, on: screen), onActiveSpace: key.onActiveSpace)
        if let plate = key.plate {
          let plateID = BarRegistryID(display: display, part: .plate, keyWindow: key.number)
          entries[plateID] = .init(pixels: BarPixels.pixels(plate, display: screen.frame, scale: scale),
                                   alpha: key.alpha, level: key.level, window: key.number,
                                   mask: .none, onActiveSpace: key.onActiveSpace)
        }
      }
      displays[display] = .init(frame: screen.frame, scale: scale,
                                scene: .classify(evidence[display], screenPresent: true),
                                bandEnabled: bar != nil, blackBottom: BarRegistry.blackBottom(band: band, edge: edge))
    }
    return .init(entries: entries, displays: displays)
  }
}
