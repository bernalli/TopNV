/// Decisions for a single display. Space membership is supplied by NSWindow, never guessed
/// from a Space number. Inactive windows retain their last gate while the desktop slides.
/// `forget` does not return a creation to the visit budget: an adapter that closes windows
/// for its own reasons (option off, new geometry) starts again from a new value.
public struct KeyedOverlayState {
  public enum Appearance: Sendable { case light, dark, unknown }
  public enum Context: Sendable { case desktop, slidingDesktop, fullScreen, unknown }

  public struct Input {
    public let activeWindowIDs: [Int]
    public let appearance: Appearance
    public let context: Context
    public let menuVisible: Bool
    public let enabled: Bool
    public let now: Double
    public let desktopRevealed: Bool

    public init(activeWindowIDs: [Int], appearance: Appearance, context: Context,
                menuVisible: Bool, enabled: Bool, now: Double, desktopRevealed: Bool = false) {
      self.activeWindowIDs = activeWindowIDs
      self.appearance = appearance
      self.context = context
      self.menuVisible = menuVisible
      self.enabled = enabled
      self.now = now
      self.desktopRevealed = desktopRevealed
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
    settleUntil = now + 0.5
  }

  public mutating func update(_ input: Input) -> Decision {
    var result = Decision()
    let active = Set(input.activeWindowIDs).sorted()
    let keeper = active.first
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
    lastActive = keeper
    result.close = Array(active.dropFirst())
    for id in result.close { visibility[id] = nil }
    let settled = input.now >= settleUntil
    let show = input.enabled && input.appearance == .light
      && input.context == .desktop && input.menuVisible
    if let keeper {
      // While the evidence settles after a Space change the window keeps the gate it had
      // when its Space was last active. Hiding it here turns the bar grey after every switch.
      // While both desktops are sliding the menu can disappear and the appearance probe
      // still belongs to the departing Space. Neither should change either window's gate.
      let sliding = input.context == .slidingDesktop && input.enabled && input.appearance != .unknown
      if settled && !sliding {
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
