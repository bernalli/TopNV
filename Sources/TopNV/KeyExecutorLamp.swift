import AppKit
import TopNVCore
import os

/// The underlay is shared across Spaces. Only the active key on each display owns its light.
@MainActor
final class KeyLamp {
  @MainActor private struct Presentation {
    let window: OverlayWindow
    let owner: Int
    let frame: CGRect
    let mask: BarMask
    let alpha: CGFloat

    var matchesWindow: Bool {
      guard let strip = window.contentView as? BarStripView else { return false }
      return window.windowNumber > 0 && window.isVisible && window.level == KeyLamp.level
        && window.frame == frame && window.alphaValue == alpha && strip.matches(mask, in: window)
    }
  }

  private static let logger = Logger(subsystem: "TopNV", category: "Lamp")
  static let level = NSWindow.Level(rawValue: OverlayLevel.bar.rawValue + 1)
  private let create: @MainActor (CGRect) -> OverlayWindow?
  private let log: (String) -> Void
  private var presentations: [UInt32: Presentation] = [:]

  init(makeWindow: @escaping @MainActor (CGRect) -> OverlayWindow? = { KeyLamp.makeWindow($0) },
       log: ((String) -> Void)? = nil) {
    create = makeWindow
    self.log = log ?? { KeyLamp.logger.info("\($0, privacy: .public)") }
  }

  static func makeWindow(_ frame: CGRect) -> OverlayWindow {
    OverlayWindow(frame: frame, level: level, isOpaque: true, behavior: OverlayBehavior.bar)
  }

  func window(on display: UInt32) -> OverlayWindow? { presentations[display]?.window }

  func verify(on display: UInt32, owner: Int) throws {
    if let current = presentations[display], current.owner == owner, !current.matchesWindow {
      throw BackdropFailure(reason: "lamp readback differs")
    }
  }

  func apply(_ plan: BarDisplayPlan, display: UInt32, owner: Int, alpha: CGFloat) throws {
    guard let frame = plan.key.frame else { throw BackdropFailure(reason: "missing lamp frame") }
    let previous = presentations[display]
    let window: OverlayWindow
    if let previous {
      guard previous.matchesWindow else { throw BackdropFailure(reason: "lamp readback differs") }
      window = previous.window
    } else {
      guard let created = create(frame) else { throw BackdropFailure(reason: "lamp window unavailable") }
      window = created
      window.alphaValue = 0
      window.backgroundColor = .white
      _ = BarStripView(in: window, color: .white)
    }
    let current = Presentation(window: window, owner: owner, frame: frame, mask: plan.key.mask, alpha: alpha)
    presentations[display] = current
    if window.frame != frame { window.setFrame(frame, display: false) }
    (window.contentView as? BarStripView)?.apply(current.mask, to: window)
    window.applyAlpha(.value(alpha))
    if !window.isVisible { window.orderFrontRegardless() }
    guard current.matchesWindow else { throw BackdropFailure(reason: "lamp presentation differs") }
    if previous?.alpha != alpha || previous?.owner != owner {
      let pixels = plan.band.pixels?.description ?? "none"
      log("Lamp display=\(display) alpha=\(alpha) px=\(pixels) state=present")
    }
  }

  func close(_ display: UInt32, owner: Int? = nil) {
    guard let current = presentations[display], owner == nil || current.owner == owner else { return }
    presentations.removeValue(forKey: display)
    current.window.alphaValue = 0
    current.window.close()
    log("Lamp display=\(display) alpha=0 state=closed")
  }
}
