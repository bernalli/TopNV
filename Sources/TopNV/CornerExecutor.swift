import AppKit
import TopNVCore

@MainActor
final class CornerExecutor: BarPartExecuting {
  private var windows: [String: CornerWindow] = [:]

  @discardableResult
  func apply(_ plan: BarPlan) -> BarEntries {
    var entries: BarEntries = [:]
    var retained: Set<String> = []
    applyBarPresentation {
      for (id, display) in plan.displays {
        for (corner, part) in display.corners where part.exists {
          let key = "\(id).\(corner.rawValue)"
          let window: CornerWindow
          if let existing = windows[key] {
            window = existing
            if let frame = part.frame, window.frame != frame { window.setFrame(frame, display: false) }
          } else if let frame = part.frame {
            window = CornerWindow(corner: corner, frame: frame)
            windows[key] = window
          } else {
            continue
          }
          retained.insert(key)
          window.applyAlpha(part.alpha)
          if part.frame != nil && !window.isVisible { window.orderFrontRegardless() }
          entries[.init(display: id, part: .corner(corner))] = window.registryEntry(on: display.geometry)
        }
      }
      for key in windows.keys where !retained.contains(key) { windows.removeValue(forKey: key)?.close() }
    }
    return entries
  }

  func closeAll() {
    for window in windows.values { window.close() }
    windows.removeAll()
  }
}
