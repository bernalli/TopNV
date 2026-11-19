import AppKit
import TopNVCore

@MainActor
final class EdgeExecutor: BarPartExecuting {
  private var windows: [UInt32: OverlayWindow] = [:]

  @discardableResult
  func apply(_ plan: BarPlan) -> BarEntries {
    var entries: BarEntries = [:]
    applyBarPresentation {
      for id in windows.keys where plan.displays[id]?.edge.exists != true {
        windows.removeValue(forKey: id)?.close()
      }
      for (id, display) in plan.displays where display.edge.exists {
        let part = display.edge
        let key = BarRegistryID(display: id, part: .edge)
        guard let frame = part.frame, part.alpha != .value(0) else {
          if let window = windows[id] {
            if window.isVisible { window.orderOut(nil) }
            (window.contentView as? BarStripView)?.apply(.none, to: window)
            entries[key] = window.registryEntry(on: display.geometry)
          }
          continue
        }
        let window: OverlayWindow
        if let existing = windows[id] {
          window = existing
        } else {
          window = OverlayWindow(frame: frame, level: .init(rawValue: MenuBarEvidence.overlayLevel + 1),
                                 isOpaque: true, behavior: OverlayBehavior.bar)
          _ = BarStripView(in: window)
          windows[id] = window
        }
        let moved = window.frame != frame
        if moved { window.setFrame(frame, display: false) }
        (window.contentView as? BarStripView)?.apply(part.mask, to: window)
        window.applyAlpha(part.alpha)
        if moved || !window.isVisible { window.orderFrontRegardless() }
        entries[key] = window.registryEntry(on: display.geometry, mask: part.mask)
      }
    }
    return entries
  }

  func closeAll() {
    for window in windows.values { window.close() }
    windows.removeAll()
  }
}
