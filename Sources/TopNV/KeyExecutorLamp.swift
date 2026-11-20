import AppKit
import TopNVCore
import os

/// One white underlay for each two-layer key. A lamp is ordered in with its key, so it joins the
/// same Space, and it takes the alpha and mask of that key in the same transaction.
@MainActor
final class KeyLamp {
  @MainActor private struct Presentation {
    let window: OverlayWindow
    let display: UInt32
    let frame: CGRect
    let mask: BarMask
    let alpha: CGFloat

    /// Everything except visibility, which only the ordering in the creation sequence gives.
    var matchesContent: Bool {
      guard let strip = window.contentView as? BarStripView else { return false }
      return window.windowNumber > 0 && window.level == KeyLamp.level && window.collectionBehavior == KeyLamp.behavior
        && window.frame == frame && window.alphaValue == alpha && strip.matches(mask, in: window)
    }

    var matchesWindow: Bool { matchesContent && window.isVisible }
  }

  private static let logger = Logger(subsystem: "TopNV", category: "Lamp")
  /// Above the black band, below the key and the system menu.
  static let level = NSWindow.Level(rawValue: OverlayLevel.bar.rawValue + 1)
  /// The Space behavior of the key: a lamp never stays behind on another Space.
  static let behavior = OverlayBehavior.keyed
  private let newWindow: @MainActor (CGRect) -> OverlayWindow?
  private let log: (String) -> Void
  private var presentations: [Int: Presentation] = [:]

  init(makeWindow: @escaping @MainActor (CGRect) -> OverlayWindow? = { KeyLamp.makeWindow($0) },
       log: ((String) -> Void)? = nil) {
    newWindow = makeWindow
    self.log = log ?? { KeyLamp.logger.info("\($0, privacy: .public)") }
  }

  static func makeWindow(_ frame: CGRect) -> OverlayWindow {
    OverlayWindow(frame: frame, level: level, isOpaque: true, behavior: behavior)
  }

  /// The key windows that currently have a lamp.
  var keys: Set<Int> { Set(presentations.keys) }

  func window(for key: Int) -> OverlayWindow? { presentations[key]?.window }

  /// Creates the lamp of a new key, transparent and not yet ordered in. Call inside the
  /// presentation transaction, then `orderFront(for:)` together with the key.
  func create(for key: Int, display: UInt32, frame: CGRect, mask: BarMask) throws {
    guard presentations[key] == nil else { throw BackdropFailure(reason: "lamp already exists") }
    guard let window = newWindow(frame) else { throw BackdropFailure(reason: "lamp window unavailable") }
    window.alphaValue = 0
    window.backgroundColor = .white
    BarStripView(in: window, color: .white).apply(mask, to: window)
    let current = Presentation(window: window, display: display, frame: frame, mask: mask, alpha: 0)
    guard current.matchesContent else {
      window.close()
      throw BackdropFailure(reason: "lamp presentation differs")
    }
    presentations[key] = current
    log("Lamp key=\(key) display=\(display) alpha=0 state=created")
  }

  func orderFront(for key: Int) {
    presentations[key]?.window.orderFrontRegardless()
  }

  func verify(for key: Int) throws {
    guard let current = presentations[key] else { throw BackdropFailure(reason: "lamp missing") }
    guard current.matchesWindow else { throw BackdropFailure(reason: "lamp readback differs") }
  }

  /// Gives the lamp the alpha and mask that its key just received. The window is never ordered
  /// in again: ordered in while another Space is active, it would join that Space.
  func apply(_ plan: BarDisplayPlan, key: Int, alpha: CGFloat) throws {
    guard let previous = presentations[key] else { throw BackdropFailure(reason: "lamp missing") }
    guard previous.matchesWindow else { throw BackdropFailure(reason: "lamp readback differs") }
    let window = previous.window
    let current = Presentation(window: window, display: previous.display, frame: previous.frame,
                               mask: plan.key.mask, alpha: alpha)
    presentations[key] = current
    (window.contentView as? BarStripView)?.apply(current.mask, to: window)
    window.applyAlpha(.value(alpha))
    guard current.matchesWindow else { throw BackdropFailure(reason: "lamp presentation differs") }
    if previous.alpha != alpha {
      let pixels = plan.band.pixels?.description ?? "none"
      log("Lamp key=\(key) display=\(current.display) alpha=\(alpha) px=\(pixels) state=present")
    }
  }

  func close(for key: Int) {
    guard let current = presentations.removeValue(forKey: key) else { return }
    current.window.alphaValue = 0
    current.window.close()
    log("Lamp key=\(key) display=\(current.display) alpha=0 state=closed")
  }
}
