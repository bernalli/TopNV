import AppKit
import TopNVCore

@MainActor
final class BandExecutor: BarPartExecuting {
  private var windows: [UInt32: BarWindow] = [:]

  @discardableResult
  func apply(_ plan: BarPlan) -> BarEntries {
    var entries: BarEntries = [:]
    applyBarPresentation {
      for id in windows.keys where plan.displays[id]?.band.exists != true {
        windows.removeValue(forKey: id)?.close()
      }
      for (id, display) in plan.displays where display.band.exists {
        let part = display.band
        guard let frame = part.frame else { continue }
        let window: BarWindow
        if let existing = windows[id] {
          window = existing
          if window.frame != frame { window.setFrame(frame, display: false) }
        } else {
          window = BarWindow(frame: frame)
          _ = BarStripView(in: window)
          windows[id] = window
        }
        (window.contentView as? BarStripView)?.apply(part.mask, to: window)
        window.applyAlpha(part.alpha)
        if !window.isVisible { window.orderFrontRegardless() }
        entries[.init(display: id, part: .band)] = window.registryEntry(on: display.geometry, mask: part.mask)
      }
    }
    return entries
  }

  func closeAll() {
    for window in windows.values { window.close() }
    windows.removeAll()
  }
}

extension OverlayWindow {
  /// `hold` keeps the last applied alpha. Only the bar executors call this.
  func applyAlpha(_ alpha: BarAlpha) {
    if case let .value(value) = alpha, alphaValue != value { alphaValue = value }
  }
}
