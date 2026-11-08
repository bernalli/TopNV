import AppKit
import Sparkle
import TopNVCore

@MainActor
final class SparkleUpdater: NSObject, UpdaterControlling, SPUStandardUserDriverDelegate {
  var onChange: (() -> Void)?
  private var controller: SPUStandardUpdaterController!
  private var observations: [NSKeyValueObservation] = []
  private var hasPendingReminder = false

  override init() {
    super.init()
    controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
    observations = [
      controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.onChange?() }
      },
      controller.updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.onChange?() }
      },
    ]
  }
  var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
  var automaticallyChecksForUpdates: Bool {
    get { controller.updater.automaticallyChecksForUpdates }
    set { controller.updater.automaticallyChecksForUpdates = newValue }
  }
  func start() throws { try controller.updater.start() }
  func checkForUpdates() {
    RunLoop.main.perform(inModes: [.default]) { [weak self] in
      MainActor.assumeIsolated { self?.controller.checkForUpdates(nil) }
    }
  }
  var supportsGentleScheduledUpdateReminders: Bool { true }
  func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
    !immediateFocus
  }
  func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
    guard !state.userInitiated, automaticallyChecksForUpdates else { return }
    hasPendingReminder = true
    NSApp.setActivationPolicy(.regular)
    NSApp.dockTile.badgeLabel = "1"
  }
  func reopenPendingUpdate() -> Bool {
    guard hasPendingReminder else { return false }
    checkForUpdates()
    return true
  }
  func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) { clearReminder() }
  func standardUserDriverWillFinishUpdateSession() { clearReminder() }
  private func clearReminder() {
    guard hasPendingReminder else { return }
    hasPendingReminder = false
    NSApp.dockTile.badgeLabel = nil
    NSApp.setActivationPolicy(.accessory)
  }
}
