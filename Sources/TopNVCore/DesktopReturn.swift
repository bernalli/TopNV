import CoreGraphics

/// One display's ordinary window positions and the windows seen leaving them during a reveal.
public struct DesktopReturn {
  private var ordinary: [CGWindowID: CGRect] = [:]
  private var displaced: [CGWindowID: CGRect] = [:]
  private var surfaceNumber: CGWindowID?
  private var overviewFading = false
  private var overviewWasOpaque = false
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
      if !missedSurface, !overviewFading, returningWindow == nil, windows.contains(where: stillDisplaced) {
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
      overviewFading = false
      overviewWasOpaque = false
      surfaceNumber = surface.number
    }
    guard surfaceNumber != nil, surface.layer == 18 || surface.layer == 19,
          evidence.menuVisible || evidence.context == .fullScreen else { return evidence }
    let overview = surface.layer == 19 && surface.isWindowManager
    if overview && surface.alpha == 1 { overviewWasOpaque = true }
    overviewFading = overview && overviewWasOpaque && surface.alpha < 0.99
    for window in windows where isDocument(window) {
      observe(window, interior: interior, showDesktop: surface.isWindowManager && surface.layer == 18)
    }
    var result = evidence
    result.revealOverride = returningWindow == nil && !overviewFading
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
    if !showDesktop {
      observeThumbnail(number, bounds: bounds, home: home)
      return
    }

    // Show Desktop leaves a narrow sliver at the edge. The same document, at its
    // original size, must move back towards its own desktop position.
    guard bounds.size == home.size else { return }
    let back = displaced[number].map { distance(bounds, home) + 2 < distance($0, home) } ?? false
    if !bounds.intersects(interior) {
      displaced[number] = bounds
      if returningWindow == number { returningWindow = nil }
    } else if back && displaced[number] != nil {
      returningWindow = number
    }
  }

  private mutating func observeThumbnail(_ number: CGWindowID, bounds: CGRect, home: CGRect) {
    let previous = displaced[number]
    if let previous, bounds == home || (
      bounds.width > previous.width + 2 && bounds.height > previous.height + 2
      && bounds.width <= home.width + 2 && bounds.height <= home.height + 2
      && distance(bounds, home) <= distance(previous, home) + 2
    ) {
      returningWindow = number
    } else if let previous, bounds.width < previous.width - 2 && bounds.height < previous.height - 2,
              returningWindow == number {
      returningWindow = nil
    }
    if previous != nil || (bounds.width < home.width - 2 && bounds.height < home.height - 2) {
      displaced[number] = bounds
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
