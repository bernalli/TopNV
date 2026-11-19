import CoreGraphics

/// Decides band operations without a window server. A Space transition never changes the
/// geometry. A screen-configuration event is not trusted blindly either: wake and display events
/// can arrive while a full-screen Space hides the menu bar or the notch area. So for a display
/// that keeps its screen size the band never shrinks and never closes; it can only grow.
public struct BandState: Sendable {
  public enum Event: Sendable {
    case screenConfigurationChanged
    case settingsChanged
    case spaceChanged
  }

  public struct Screen: Sendable {
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

  public enum Action: Equatable, Sendable {
    case show(displayID: UInt32, frame: CGRect)
    case close(displayID: UInt32)
  }

  /// The screen size of a display at its last good measure, and the band height found then.
  private struct Memory: Sendable {
    let size: CGSize
    let height: CGFloat
  }

  /// Frames of the currently requested windows; also positions the corners below the band.
  public private(set) var frames: [UInt32: CGRect] = [:]
  private var confirmedFrames: [UInt32: CGRect] = [:]
  /// Outlives a display that leaves the list, so the same display returns at its good height.
  private var memories: [UInt32: Memory] = [:]

  public init() {}

  public mutating func update(
    _ event: Event, screens: [Screen], hideNotch: Bool
  ) -> [Action] {
    // Even an empty or changed screen list during a Space switch is not a topology change.
    guard event != .spaceChanged else { return [] }

    if event == .screenConfigurationChanged {
      confirmedFrames.removeAll()
      for screen in screens {
        let frame = confirmedFrame(for: screen)
        confirmedFrames[screen.id] = frame
        memories[screen.id] = frame.map { Memory(size: screen.frame.size, height: $0.height) }
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

  /// The measured band, or the remembered one when the display kept its screen size and the
  /// measure is lower or missing. A different size, or a display never seen, takes the measure.
  private func confirmedFrame(for screen: Screen) -> CGRect? {
    let measured = BarGeometry.barRect(
      frame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: screen.safeAreaTop)
    guard let memory = memories[screen.id], memory.size == screen.frame.size else {
      return measured
    }
    if let measured, measured.height >= memory.height { return measured }
    return CGRect(
      x: screen.frame.minX, y: screen.frame.maxY - memory.height, width: screen.frame.width,
      height: memory.height)
  }
}
