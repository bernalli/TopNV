import Combine

/// What the menu shows of the updater.
public enum UpdateItems: Equatable, Sendable {
  /// No updater, or it could not start: the menu has no update items.
  case hidden
  /// The updater waits for the answer to the first-launch question: the items are shown, dimmed.
  case waiting
  case ready(canCheck: Bool, checksAutomatically: Bool)

  public var isReady: Bool {
    if case .ready = self { return true }
    return false
  }

  public var canCheck: Bool {
    if case .ready(let canCheck, _) = self { return canCheck }
    return false
  }

  public var checksAutomatically: Bool {
    if case .ready(_, let checksAutomatically) = self { return checksAutomatically }
    return false
  }
}

@MainActor
public final class UpdateMenuModel: ObservableObject {
  @Published public private(set) var isAvailable = false
  /// True from launch until the updater starts or fails, when there is an updater.
  @Published public private(set) var isWaiting: Bool
  @Published public private(set) var canCheckForUpdates = false
  @Published public private(set) var automaticallyChecksForUpdates = false
  private let updater: UpdaterControlling?
  private let schedule: (@escaping @MainActor () -> Void) -> Void
  public init(updater: UpdaterControlling?, schedule: @escaping (@escaping @MainActor () -> Void) -> Void = { action in
    Task { @MainActor in action() }
  }) {
    self.updater=updater; self.schedule=schedule
    isWaiting = updater != nil
  }
  public var items: UpdateItems {
    if isAvailable {
      return .ready(canCheck: canCheckForUpdates, checksAutomatically: automaticallyChecksForUpdates)
    }
    return isWaiting ? .waiting : .hidden
  }
  public func updaterDidStart() {
    guard updater != nil else { return }
    if isWaiting { isWaiting=false }
    if !isAvailable { isAvailable=true }
    refresh()
  }
  /// The updater could not start: the menu drops the update items. After a start it changes nothing.
  public func updaterDidFail() {
    guard !isAvailable, isWaiting else { return }
    isWaiting=false
  }
  public func checkForUpdates() {
    guard isAvailable, let updater, updater.canCheckForUpdates else { return }
    updater.checkForUpdates()
  }
  public func setAutomaticallyChecks(_ enabled: Bool) {
    guard isAvailable, let updater else { return }
    updater.automaticallyChecksForUpdates=enabled
    refresh()
  }
  public func updaterDidChange() {
    schedule { [weak self] in self?.refresh() }
  }
  private func refresh() {
    guard isAvailable, let updater else { return }
    let canCheck=updater.canCheckForUpdates, automatic=updater.automaticallyChecksForUpdates
    if canCheckForUpdates != canCheck { canCheckForUpdates=canCheck }
    if automaticallyChecksForUpdates != automatic { automaticallyChecksForUpdates=automatic }
  }
}
