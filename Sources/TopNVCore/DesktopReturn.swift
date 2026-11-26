import CoreGraphics

/// One display's ordinary window positions and the windows seen leaving them during a reveal.
public struct DesktopReturn {
  private var ordinary: [CGWindowID: CGRect] = [:]
  private var parked: [CGWindowID: CGRect] = [:]
  private var thumbnails: [CGWindowID: CGRect] = [:]
  private var desktopBand: (number: CGWindowID, frame: CGRect)?
  private var surfaceNumber: CGWindowID?
  private var surfaceLayer: Int?
  private var surfaceFading = false
  private var alphaExtreme: Double?
  private var bandListing = OverviewBandListing()
  private var missedSurface = false
  private var returningWindow: CGWindowID?

  public init() {}

  public mutating func resolve(_ evidence: MenuBarEvidence.Result, on frame: CGRect,
                               windows: [MenuBarEvidence.Window]?,
                               band: (number: CGWindowID, frame: CGRect)? = nil) -> MenuBarEvidence.Result {
    guard evidence.permitsBandEntrance, let windows else {
      self = Self()
      return evidence
    }
    let interior = frame.insetBy(dx: 16, dy: 16)
    let documents = Self.documents(in: windows)
    guard let surface = evidence.revealSurface else {
      // One sample without the surface decides nothing: a reveal whose documents are still
      // displaced stays a reveal, and a return that has started is neither cancelled nor replayed.
      let hasParked = hasParkedDocument(documents, frame: frame, interior: interior)
      let hasDisplaced = hasParked || hasThumbnailDocument(documents)
      let returning = returningWindow != nil
        || ((bandListing.returned || surfaceFading) && !(surfaceLayer == 18 && hasParked))
      if !missedSurface, returning || hasDisplaced {
        missedSurface = true
        guard !returning else { return evidence }
        var held = evidence
        held.revealOverride = true
        return held
      }
      rememberDesktop(documents, interior: interior, windows: windows, band: band)
      return evidence
    }
    missedSurface = false
    if surfaceNumber != surface.number || surfaceLayer != surface.layer {
      resetForSurface(surface)
    }
    guard surfaceNumber != nil, surface.layer == 18 || surface.layer == 19 else { return evidence }
    let wasFading = surfaceFading
    if surface.isWindowManager || surface.isDock { observeSurfaceAlpha(surface.alpha) }
    guard evidence.menuVisible || evidence.context == .fullScreen else {
      bandListing = OverviewBandListing()
      return evidence
    }
    let showDesktop = surface.isWindowManager && surface.layer == 18
    let isOverview = (surface.isWindowManager && surface.layer == 19) || (surface.isDock && surface.layer == 18)
    let wasReturning = returningWindow != nil || bandListing.returned
    let thumbnailShrank = observeDocuments(documents, frame: frame, interior: interior,
                                           showDesktop: showDesktop, allowParked: showDesktop || surface.isDock)
    var result = evidence
    // A fading or relisting reveal cannot prove a return while known windows are still parked.
    let parkedOnReveal = (showDesktop || surface.isDock)
      && hasParkedDocument(documents, frame: frame, interior: interior)
    if isOverview {
      let reversed = (wasFading && !surfaceFading) || (wasReturning && thumbnailShrank)
      bandListing.observe(band: !reversed && !parkedOnReveal && evidence.menuBounds != nil ? band : nil,
                          in: windows, surfaceAlpha: surface.alpha)
    }
    let returning = returningWindow != nil || ((bandListing.returned || surfaceFading) && !parkedOnReveal)
    result.revealOverride = !returning
    return result
  }

  private mutating func resetForSurface(_ surface: MenuBarEvidence.Window) {
    let seededBand = surfaceNumber == nil ? desktopBand : nil
    desktopBand = nil
    parked.removeAll(keepingCapacity: true)
    thumbnails.removeAll(keepingCapacity: true)
    returningWindow = nil
    surfaceFading = false
    bandListing = OverviewBandListing(seededBand: seededBand)
    alphaExtreme = nil
    surfaceLayer = surface.layer
    surfaceNumber = surface.number
  }

  private func hasParkedDocument(_ documents: [CGWindowID: CGRect], frame: CGRect, interior: CGRect) -> Bool {
    documents.contains { number, bounds in
      guard let anchor = parked[number], let home = ordinary[number],
            abs(bounds.width - home.width) <= 2, abs(bounds.height - home.height) <= 2 else { return false }
      let currentDistance = distance(bounds, home)
      return currentDistance + 2 >= distance(anchor, home)
        && isAtEdge(bounds, currentDistance: currentDistance, frame: frame, interior: interior)
    }
  }

  private func isAtEdge(_ bounds: CGRect, currentDistance: CGFloat, frame: CGRect, interior: CGRect) -> Bool {
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    return !bounds.intersects(interior) || (!frame.contains(center) && currentDistance > 60)
  }

  private func hasThumbnailDocument(_ documents: [CGWindowID: CGRect]) -> Bool {
    documents.contains { thumbnails[$0.key] == $0.value }
  }

  /// Follow the same system window through a fade, even if the sampler missed its peak.
  /// Compare against its last extremum so small changes accumulate and jitter does not rearm it.
  private mutating func observeSurfaceAlpha(_ alpha: Double) {
    let previous = alphaExtreme ?? alpha
    if surfaceFading {
      if alpha > previous + 0.01 {
        surfaceFading = false
        alphaExtreme = alpha
      } else {
        alphaExtreme = min(previous, alpha)
      }
    } else if alpha < previous - 0.01 {
      surfaceFading = true
      alphaExtreme = alpha
    } else {
      alphaExtreme = max(previous, alpha)
    }
  }

  private mutating func rememberDesktop(_ documents: [CGWindowID: CGRect], interior: CGRect,
                                        windows: [MenuBarEvidence.Window],
                                        band: (number: CGWindowID, frame: CGRect)?) {
    self = Self()
    ordinary = documents.filter { interior.contains(CGPoint(x: $0.value.midX, y: $0.value.midY)) }
    if let band, Self.isBandListedOnDesktop(band, in: windows) {
      desktopBand = band
    }
  }

  private static func isBandListedOnDesktop(_ band: (number: CGWindowID, frame: CGRect),
                                            in windows: [MenuBarEvidence.Window]) -> Bool {
    var iterator = windows.lazy.filter { $0.number == band.number }.makeIterator()
    guard let window = iterator.next(), iterator.next() == nil else { return false }
    return window.owner == .ownApp && window.alpha > 0 && OverviewBandListing.matchesFrame(window.bounds, band.frame)
  }

  private mutating func observeDocuments(_ documents: [CGWindowID: CGRect], frame: CGRect, interior: CGRect,
                                         showDesktop: Bool, allowParked: Bool) -> Bool {
    var thumbnailShrank = false
    // In window number order: the outcome never depends on the order of a dictionary.
    for (number, bounds) in documents.sorted(by: { $0.key < $1.key }) {
      guard let home = ordinary[number] else { continue }
      if showDesktop {
        observeParkedDocument(number, bounds: bounds, home: home, frame: frame, interior: interior)
      } else {
        if allowParked {
          observeParkedDocument(number, bounds: bounds, home: home, frame: frame, interior: interior)
        }
        if observeThumbnail(number, bounds: bounds, home: home) {
          thumbnailShrank = true
        }
      }
    }
    return thumbnailShrank
  }

  private mutating func observeParkedDocument(_ number: CGWindowID, bounds: CGRect, home: CGRect,
                                              frame: CGRect, interior: CGRect) {
    // Show Desktop leaves a narrow sliver at the edge. The same document, at its
    // original size (within 2 pt rounding), must move back towards its own desktop position.
    guard abs(bounds.width - home.width) <= 2, abs(bounds.height - home.height) <= 2 else { return }
    let currentDistance = distance(bounds, home)
    let atEdge = isAtEdge(bounds, currentDistance: currentDistance, frame: frame, interior: interior)
    if let anchor = parked[number] {
      let anchorDistance = distance(anchor, home)
      if currentDistance + 2 < anchorDistance {
        returningWindow = number
      } else if atEdge {
        if currentDistance >= anchorDistance { parked[number] = bounds }
        if returningWindow == number { returningWindow = nil }
      }
    } else if atEdge {
      parked[number] = bounds
      if returningWindow == number { returningWindow = nil }
    }
  }

  private mutating func observeThumbnail(_ number: CGWindowID, bounds: CGRect, home: CGRect) -> Bool {
    let previous = thumbnails[number]
    let shrinking = previous.map { bounds.width < $0.width - 2 && bounds.height < $0.height - 2 } ?? false
    if let previous, bounds == home || (
      bounds.width > previous.width + 2 && bounds.height > previous.height + 2
      && bounds.width <= home.width + 2 && bounds.height <= home.height + 2
      && distance(bounds, home) <= distance(previous, home) + 2
    ) {
      returningWindow = number
    } else if shrinking && returningWindow == number {
      returningWindow = nil
    }
    if previous != nil || (bounds.width < home.width - 2 && bounds.height < home.height - 2) {
      thumbnails[number] = bounds
    }
    return shrinking
  }

  /// Bounds of the documents by window number. A number listed twice identifies no window.
  private static func documents(in windows: [MenuBarEvidence.Window]) -> [CGWindowID: CGRect] {
    var result: [CGWindowID: CGRect] = [:]
    var repeated: Set<CGWindowID> = []
    for window in windows where isDocument(window) {
      guard let number = window.number else { continue }
      if result.updateValue(window.bounds, forKey: number) != nil { repeated.insert(number) }
    }
    for number in repeated { result[number] = nil }
    return result
  }

  private static func isDocument(_ window: MenuBarEvidence.Window) -> Bool {
    window.owner == .application && window.layer == 0 && window.alpha > 0 && !window.bounds.isEmpty
  }

  private func distance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
    hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY)
  }
}
