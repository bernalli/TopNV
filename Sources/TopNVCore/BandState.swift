import CoreGraphics

/// Decides band operations without a window server. Space notifications preserve geometry.
/// A measured menu can resize the band. Until then, keep the tallest fallback at the same
/// screen size because wake and display events can arrive with the menu or notch area hidden.
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

  private enum MenuObservation: Equatable, Sendable {
    case measured(CGFloat)
    case unlisted
    case unavailable
  }

  private struct Memory: Sendable {
    let size: CGSize
    let fallbackHeight: CGFloat
    var safeAreaTop: CGFloat
    var menuDepth: CGFloat?

    func frame(on screen: CGRect) -> CGRect {
      let height = min(screen.height, max(menuDepth ?? fallbackHeight, safeAreaTop))
      return BarGeometry.topStrip(frame: screen, height: height)
    }
  }

  /// Frames of the currently requested windows; also positions the corners below the band.
  public private(set) var frames: [UInt32: CGRect] = [:]
  private var confirmedFrames: [UInt32: CGRect] = [:]
  /// Outlives a display that leaves the list, so the same display returns at its good height.
  private var memories: [UInt32: Memory] = [:]
  private var pendingMenuObservations: [UInt32: MenuObservation] = [:]

  public init() {}

  public mutating func update(
    _ event: Event, screens: [Screen], hideNotch: Bool
  ) -> [Action] {
    pendingMenuObservations.removeAll()
    // Even an empty or changed screen list during a Space switch is not a topology change.
    guard event != .spaceChanged else { return [] }

    if event == .screenConfigurationChanged {
      confirmedFrames.removeAll()
      for screen in screens {
        let memory = configurationMemory(for: screen)
        confirmedFrames[screen.id] = memory?.frame(on: screen.frame)
        memories[screen.id] = memory
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

  func menuDepth(for id: UInt32) -> CGFloat? { memories[id]?.menuDepth }

  mutating func discardMenuObservation(for id: UInt32) { pendingMenuObservations[id] = nil }

  /// A first measurement applies immediately. Changes to it need two consecutive matching samples.
  mutating func observeMenu(_ menu: CGRect?, listAvailable: Bool, on display: BarDisplay) {
    let id = display.id
    let frame = display.frame
    let pending = pendingMenuObservations.removeValue(forKey: id)
    guard let band = frames[id], var memory = memories[id], memory.size == frame.size,
          band.minX == frame.minX, band.maxY == frame.maxY else { return }
    if display.safeAreaTop > memory.safeAreaTop { memory.safeAreaTop = display.safeAreaTop }
    let depth = menu?.height
    if depth != memory.menuDepth {
      let observation = depth.map(MenuObservation.measured) ?? (listAvailable ? .unlisted : .unavailable)
      if memory.menuDepth == nil || pending == observation {
        memory.menuDepth = depth
      } else {
        pendingMenuObservations[id] = observation
      }
    }
    memories[id] = memory
    let measured = memory.frame(on: frame)
    confirmedFrames[id] = measured
    frames[id] = measured
  }

  private func configurationMemory(for screen: Screen) -> Memory? {
    let fallback = BarGeometry.barRect(
      frame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: screen.safeAreaTop)
    let previous = memories[screen.id].flatMap { $0.size == screen.frame.size ? $0 : nil }
    let height = max(fallback?.height ?? 0, previous?.fallbackHeight ?? 0)
    guard height > 0 else { return nil }
    let safeArea = screen.safeAreaTop > 0 ? screen.safeAreaTop : previous?.safeAreaTop ?? 0
    return Memory(size: screen.frame.size, fallbackHeight: height, safeAreaTop: safeArea,
                  menuDepth: previous?.menuDepth)
  }
}
