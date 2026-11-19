/// Decisions for a single display. Space membership is supplied by NSWindow, never guessed
/// from a Space number. Inactive windows retain their last gate while the desktop slides.
/// `forget` does not return a creation to the visit budget: an adapter that closes windows
/// for its own reasons (option off, new geometry) starts again from a new value.
public struct KeyedOverlayState {
  public enum Appearance: Sendable { case light, dark, unknown }
  public enum Context: Sendable { case desktop, fullScreen, unknown }

  public struct Input {
    public let activeWindowIDs: [Int]
    public let appearance: Appearance
    public let context: Context
    public let menuVisible: Bool
    public let enabled: Bool
    public let now: Double
    public let desktopRevealed: Bool
    /// The desktop of the display slides in a Space switch: the samples mix two Spaces.
    public let spaceSliding: Bool
    public let nativeFullScreen: Bool

    public init(activeWindowIDs: [Int], appearance: Appearance, context: Context,
                menuVisible: Bool, enabled: Bool, now: Double, desktopRevealed: Bool = false,
                spaceSliding: Bool = false, nativeFullScreen: Bool = false) {
      self.activeWindowIDs = activeWindowIDs
      self.appearance = appearance
      self.context = context
      self.menuVisible = menuVisible
      self.enabled = enabled
      self.now = now
      self.desktopRevealed = desktopRevealed
      self.spaceSliding = spaceSliding
      self.nativeFullScreen = nativeFullScreen
    }
  }

  public struct Reservation: Equatable {
    fileprivate let generation: UInt64
    fileprivate let serial: UInt64
  }

  public struct Decision {
    public var close: [Int] = []
    public var gates: [Int: Bool] = [:]
    public var create: Reservation?
    public fileprivate(set) var keyChange: (windowID: Int, key: LuminanceKey)?
  }

  public private(set) var visibility: [Int: Bool] = [:]
  public private(set) var creationsThisVisit = 0
  private var generation: UInt64 = 0
  private var serial: UInt64 = 0
  private var pending: Reservation?
  private var lastActive: Int?
  private var departureCandidate: Int?
  private var nextCreation = 0.0
  private var settleUntil = 0.0
  /// The first sliding sample since the last notification or the last settled sample at rest.
  private var slidingSince: Double?
  /// The evidence is trusted again this long after a notification or the last sliding sample.
  private static let settleTime = 0.5
  /// Sliding samples postpone the decision only this long without a notification: a slide
  /// signal that never ends must not keep a window shown, or keep a display without one.
  private static let longestSlide = 3.0

  public init() {}

  /// Replacing every window invalidates its gate and reservation. Space evidence still settles
  /// on the original deadline.
  public mutating func resetForWindowReplacement() {
    visibility.removeAll()
    creationsThisVisit = 0
    generation &+= 1
    pending = nil
    lastActive = nil
    departureCandidate = nil
    nextCreation = 0
  }

  /// Notifications alone are not proof of a new visit. In particular, repeated notifications
  /// cannot reset the cap when a newly ordered window never acquires Space membership.
  public mutating func spaceDidChange(now: Double) {
    generation &+= 1
    pending = nil
    if departureCandidate == nil, let lastActive { departureCandidate = lastActive }
    settleUntil = now + Self.settleTime
    // The notification ends a slide: the next one is measured from its own first sample.
    slidingSince = nil
  }

  public mutating func update(_ input: Input) -> Decision {
    var result = Decision()
    // The notification of a Space switch comes when the slide ends. During the slide the menu
    // bar and the appearance belong to two Spaces at once, so every sliding sample postpones
    // the decision as the notification does. A window keeps the gate of its own Space.
    if input.spaceSliding {
      let since = slidingSince ?? input.now
      slidingSince = since
      if input.now - since <= Self.longestSlide {
        settleUntil = max(settleUntil, input.now + Self.settleTime)
      }
    } else if input.now >= settleUntil {
      slidingSince = nil
    }
    let active = Set(input.activeWindowIDs).sorted()
    if let departureCandidate, input.now >= settleUntil {
      // A notification plus the settled departure of its confirmed window is
      // evidence of another visit. A transient membership drop alone is not.
      if !active.contains(departureCandidate) {
        creationsThisVisit = 0
        generation &+= 1
        pending = nil
      }
      self.departureCandidate = nil
    }
    let settled = input.now >= settleUntil
    // Only a settled native full-screen Space relinquishes its last keyed window.
    // On a desktop a covering borderless window can come and go without spending a creation.
    let closeAll = settled && input.context == .fullScreen && input.nativeFullScreen
    let keeper = closeAll ? nil : active.first
    lastActive = keeper
    result.close = active.filter { $0 != keeper }
    for id in result.close { visibility[id] = nil }
    let show = input.enabled && input.appearance == .light
      && input.context == .desktop && input.menuVisible
    if let keeper {
      // While the evidence settles after a Space change the window keeps the gate it had
      // when its Space was last active. Hiding it here turns the bar grey after every switch.
      if settled || !input.enabled {
        visibility[keeper] = show
        result.gates[keeper] = show
        if show {
          result.keyChange = (keeper, LuminanceKey.choose(desktopRevealed: input.desktopRevealed))
        }
      }
      pending = nil
    } else if settled && show && pending == nil && creationsThisVisit < 3
      && input.now >= nextCreation {
      creationsThisVisit += 1
      serial &+= 1
      let reservation = Reservation(generation: generation, serial: serial)
      pending = reservation
      result.create = reservation
      nextCreation = input.now + 0.5
    } else if !show {
      pending = nil
    }
    return result
  }

  /// A creation can complete only once and only in the visit that reserved it. The adapter
  /// must close a rejected window. New windows stay transparent until membership is observed.
  public mutating func commit(_ reservation: Reservation, windowID: Int) -> Bool {
    guard pending == reservation, reservation.generation == generation else { return false }
    pending = nil
    visibility[windowID] = false
    return true
  }

  public mutating func forget(_ windowID: Int) {
    visibility[windowID] = nil
  }
}
