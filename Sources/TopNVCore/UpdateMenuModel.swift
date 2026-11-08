import Combine

@MainActor
public final class UpdateMenuModel: ObservableObject {
  @Published public private(set) var isAvailable = false
  @Published public private(set) var canCheckForUpdates = false
  @Published public private(set) var automaticallyChecksForUpdates = false
  private let updater: UpdaterControlling?
  private let schedule: (@escaping @MainActor () -> Void) -> Void
  public init(updater: UpdaterControlling?, schedule: @escaping (@escaping @MainActor () -> Void) -> Void = { action in
    Task { @MainActor in action() }
  }) {
    self.updater=updater; self.schedule=schedule
  }
  public func updaterDidStart() {
    guard updater != nil else { return }
    if !isAvailable { isAvailable=true }
    refresh()
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
