import AppKit
import TopNVCore
import os

/// A test-copy light behind the menu material. KeyExecutor owns its lifetime and transaction.
@MainActor
final class KeyLamp {
  private static let logger = Logger(subsystem: "TopNV", category: "Lamp")
  // Just above the band (desktop + 1), still below application windows and the system menu.
  static let level = NSWindow.Level(rawValue: OverlayLevel.bar.rawValue + 1)

  private final class Window: OverlayWindow {
    var owner: Int?
    var pixels: PixelRect?
  }

  private var windows: [UInt32: Window] = [:]
  let enabled: () -> Bool
  private let log: (String) -> Void

  init(enabled: @escaping () -> Bool, log: ((String) -> Void)? = nil) {
    self.enabled = enabled
    self.log = log ?? { line in KeyLamp.logger.info("\(line, privacy: .public)") }
  }

  func window(on display: UInt32) -> OverlayWindow? { windows[display] }

  func apply(_ plan: BarDisplayPlan, display: UInt32, owner: Int, alpha: CGFloat) {
    guard let frame = plan.band.frame, let pixels = plan.band.pixels else { close(display); return }
    let window: Window
    if let existing = windows[display] {
      window = existing
    } else {
      window = Window(frame: frame, level: Self.level, isOpaque: true, behavior: OverlayBehavior.bar)
      window.backgroundColor = .white
      window.alphaValue = 0
      _ = BarStripView(in: window, color: .white)
      windows[display] = window
    }
    let changed = window.pixels != pixels || window.alphaValue != alpha
    window.owner = owner
    window.pixels = pixels
    if window.frame != frame { window.setFrame(frame, display: false) }
    (window.contentView as? BarStripView)?.apply(plan.key.mask, to: window)
    if window.alphaValue != alpha { window.alphaValue = alpha }
    if !window.isVisible { window.orderFrontRegardless() }
    if changed { record(window, display: display, state: "present") }
  }

  func close(_ display: UInt32, owner: Int? = nil) {
    guard let window = windows[display], owner == nil || window.owner == owner else { return }
    windows.removeValue(forKey: display)
    window.alphaValue = 0
    window.close()
    record(window, display: display, state: "closed")
  }

  private func record(_ window: Window, display: UInt32, state: String) {
    log("Lamp display=\(display) alpha=\(window.alphaValue) level=\(window.level.rawValue) "
        + "px=\(window.pixels?.description ?? "none") state=\(state)")
  }
}
