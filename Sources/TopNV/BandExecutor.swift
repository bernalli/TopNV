import AppKit
import TopNVCore

@MainActor
final class BandExecutor: BarPartExecuting {
  private var windows: [UInt32: BarWindow] = [:]

  private var cascades: [UInt32: BandCascade] = [:]

  @discardableResult
  func apply(_ plan: BarPlan) -> BarEntries {
    var entries: BarEntries = [:]
    applyBarPresentation {
      for id in windows.keys where plan.displays[id]?.band.exists != true {
        cascades.removeValue(forKey: id)?.close()
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
        if cascades[id]?.frame != frame, display.geometry != nil {
          cascades.removeValue(forKey: id)?.close()
          cascades[id] = BandCascade(frame: frame, display: id)
        }
        let cascade = cascades[id]
        let returning = display.cascadesOnReturn && cascade != nil
        let mask: BarMask = returning ? .none : part.mask
        (window.contentView as? BarStripView)?.apply(mask, to: window)
        window.applyAlpha(Self.presentationAlpha(part.alpha, returning: returning,
                                                  wasReturning: cascade?.isRunning == true))
        cascade?.apply(returning ? part.mask : .none)
        if !window.isVisible { window.orderFrontRegardless() }
        entries[.init(display: id, part: .band)] = window.registryEntry(on: display.geometry, mask: mask)
      }
    }
    return entries
  }

  static func presentationAlpha(_ alpha: BarAlpha, returning: Bool, wasReturning: Bool) -> BarAlpha {
    if returning { return .value(0) }
    // The band is logically visible during a return while the slices are drawing it.
    return wasReturning && alpha == .hold ? .value(1) : alpha
  }

  func closeAll() {
    for cascade in cascades.values { cascade.close() }
    cascades.removeAll()
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
