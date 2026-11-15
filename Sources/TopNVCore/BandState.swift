import CoreGraphics

/// Decides band operations without a window server. Only a confirmed display configuration
/// may replace the geometry: Space transitions can temporarily report no notch or a shorter bar.
public struct BandState {
  public enum Event {
    case screenConfigurationChanged
    case settingsChanged
    case spaceChanged
  }

  public struct Screen {
    public let id: UInt32
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let safeAreaTop: CGFloat

    public init(id: UInt32, frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat) {
      self.id = id
      self.frame = frame
      self.visibleFrame = visibleFrame
      self.safeAreaTop = safeAreaTop
    }
  }

  public enum Action: Equatable {
    case show(displayID: UInt32, frame: CGRect)
    case close(displayID: UInt32)
  }

  /// Frames of the currently requested windows; also positions the corners below the band.
  public private(set) var frames: [UInt32: CGRect] = [:]
  private var confirmedFrames: [UInt32: CGRect] = [:]

  public init() {}

  public mutating func update(
    _ event: Event, screens: [Screen], hideNotch: Bool
  ) -> [Action] {
    // Even an empty or changed screen list during a Space switch is not a topology change.
    guard event != .spaceChanged else { return [] }

    if event == .screenConfigurationChanged {
      confirmedFrames.removeAll()
      for screen in screens {
        confirmedFrames[screen.id] = ScreenGeometry.barRect(
          frame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: screen.safeAreaTop)
      }
    }

    let desired = hideNotch ? confirmedFrames : [:]
    var actions: [Action] = []
    for id in frames.keys.sorted() where desired[id] == nil {
      actions.append(.close(displayID: id))
    }
    for id in desired.keys.sorted() {
      guard let frame = desired[id] else { continue }
      // Wake uses the configuration event too, so an existing window can be ordered back in.
      if frames[id] != frame || event == .screenConfigurationChanged {
        actions.append(.show(displayID: id, frame: frame))
      }
    }
    frames = desired
    return actions
  }
}
