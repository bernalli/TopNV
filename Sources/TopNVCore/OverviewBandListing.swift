import CoreGraphics

/// Mission Control temporarily removes the transient band from the on-screen list.
/// An established absence and a reappearance of the same hidden band distinguish
/// an exit from the first listing on entry or a one-sample omission.
struct OverviewBandListing {
  private enum Phase {
    case idle, listed, missingOnce, absent, reappearing
    case returned(minimumAlpha: Double), missingAfterReturn(minimumAlpha: Double)
  }
  private var phase = Phase.idle
  private var number: CGWindowID?
  private var frame = CGRect.null

  var returned: Bool { minimumReturnAlpha != nil }

  private var minimumReturnAlpha: Double? {
    switch phase {
    case let .returned(alpha), let .missingAfterReturn(alpha): return alpha
    default: return nil
    }
  }

  mutating func observe(band: (number: CGWindowID, frame: CGRect)?, in windows: [MenuBarEvidence.Window],
                        surfaceAlpha: Double) {
    guard let band else {
      self = Self()
      return
    }
    if number != band.number || frame != band.frame {
      phase = .idle
      number = band.number
      frame = band.frame
    }
    // After a confirmed relist, a substantial rebound can reverse the gesture even
    // when the overview stayed at its prior opacity throughout the relist.
    let minimumAlpha = minimumReturnAlpha
    if let minimumAlpha, surfaceAlpha > minimumAlpha + 0.01 {
      phase = .idle
      return
    }
    let matching = windows.lazy.filter { $0.number == band.number }
    var iterator = matching.makeIterator()
    guard let window = iterator.next() else {
      observeMissing(at: surfaceAlpha)
      return
    }
    guard iterator.next() == nil, window.owner == .ownApp, window.bounds == frame else {
      phase = .idle
      return
    }
    if let minimumAlpha {
      phase = .returned(minimumAlpha: min(minimumAlpha, surfaceAlpha))
    } else if window.alpha == 0 {
      switch phase {
      case .absent: phase = .reappearing
      case .reappearing: phase = .returned(minimumAlpha: surfaceAlpha)
      default: phase = .listed
      }
    } else {
      phase = .idle
    }
  }

  private mutating func observeMissing(at surfaceAlpha: Double) {
    switch phase {
    case .listed: phase = .missingOnce
    case .missingOnce, .missingAfterReturn: phase = .absent
    case let .returned(alpha): phase = .missingAfterReturn(minimumAlpha: min(alpha, surfaceAlpha))
    case .reappearing: phase = .absent
    case .idle, .absent: break
    }
  }
}
