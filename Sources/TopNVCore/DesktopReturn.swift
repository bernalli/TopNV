import CoreGraphics

/// One display's ordinary window positions and the windows seen leaving them during a reveal.
public struct DesktopReturn {
  private var ordinary: [CGWindowID: CGRect] = [:]
  private var displaced: [CGWindowID: CGRect] = [:]
  private var surfaceNumber: CGWindowID?
  private var missedSurface = false
  private var returningWindow: CGWindowID?

  public init() {}

  public mutating func resolve(_ evidence: MenuBarEvidence.Result, on frame: CGRect,
                               windows: [MenuBarEvidence.Window]?) -> MenuBarEvidence.Result {
    guard evidence.permitsBandEntrance, let windows else {
      self = Self()
      return evidence
    }
    let interior = frame.insetBy(dx: 16, dy: 16)
    guard let surface = evidence.revealSurface else {
      if !missedSurface, returningWindow == nil, windows.contains(where: stillDisplaced) {
        missedSurface = true
        var held = evidence
        held.revealOverride = true
        return held
      }
      rememberDesktop(windows, interior: interior)
      return evidence
    }
    missedSurface = false
    if surfaceNumber != surface.number {
      displaced.removeAll(keepingCapacity: true)
      returningWindow = nil
      surfaceNumber = surface.number
    }
    guard surfaceNumber != nil, surface.layer == 18 || surface.layer == 19,
          evidence.menuVisible || evidence.context == .fullScreen else { return evidence }
    for window in windows where isDocument(window) {
      observe(window, interior: interior, showDesktop: surface.isWindowManager && surface.layer == 18)
    }
    var result = evidence
    result.revealOverride = returningWindow == nil
    return result
  }

  private mutating func rememberDesktop(_ windows: [MenuBarEvidence.Window], interior: CGRect) {
    self = Self()
    for window in windows where isDocument(window) {
      if let number = window.number, interior.contains(CGPoint(x: window.bounds.midX, y: window.bounds.midY)) {
        ordinary[number] = window.bounds
      }
    }
  }

  private mutating func observe(_ window: MenuBarEvidence.Window, interior: CGRect, showDesktop: Bool) {
    guard let number = window.number, let home = ordinary[number] else { return }
    let bounds = window.bounds
    let away: Bool
    let back: Bool
    if showDesktop {
      // Show Desktop leaves a narrow sliver at the edge. The same document, at its
      // original size, must move back towards its own desktop position.
      guard bounds.size == home.size else { return }
      away = !bounds.intersects(interior)
      back = displaced[number].map { distance(bounds, home) + 2 < distance($0, home) } ?? false
    } else {
      // Moving or rearranging thumbnails in Mission Control is not an exit.
      away = bounds.width < home.width - 2 && bounds.height < home.height - 2
      back = bounds == home
    }
    if away {
      displaced[number] = bounds
      if returningWindow == number { returningWindow = nil }
    } else if back && displaced[number] != nil {
      returningWindow = number
    }
  }

  private func stillDisplaced(_ window: MenuBarEvidence.Window) -> Bool {
    guard let number = window.number, isDocument(window) else { return false }
    return displaced[number] == window.bounds
  }

  private func isDocument(_ window: MenuBarEvidence.Window) -> Bool {
    window.owner == .application && window.layer == 0 && window.alpha > 0 && !window.bounds.isEmpty
  }

  private func distance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY)
  }
}
