import AppKit
import Sparkle
import TopNVCore

/// Sparkle's updater with the compact update window shared with MonoPods.
@MainActor
final class SparkleUpdater: NSObject, UpdaterControlling {
  var onChange: (() -> Void)?
  /// Kept here as well: the updater's own reference to its driver is not public.
  let userDriver: any SPUUserDriver
  private let updater: SPUUpdater
  private var observations: [NSKeyValueObservation] = []

  override init() {
    let driver = AppleStyleUpdateDriver(hostBundle: .main)
    userDriver = driver
    updater = SPUUpdater(
      hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: nil)
    super.init()
    observations = [
      updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.onChange?() }
      },
      updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
        Task { @MainActor in self?.onChange?() }
      },
    ]
  }
  var canCheckForUpdates: Bool { updater.canCheckForUpdates }
  var automaticallyChecksForUpdates: Bool {
    get { updater.automaticallyChecksForUpdates }
    set { updater.automaticallyChecksForUpdates = newValue }
  }
  func start() throws { try updater.start() }
  func checkForUpdates() {
    RunLoop.main.perform(inModes: [.default]) { [weak self] in
      MainActor.assumeIsolated { self?.updater.checkForUpdates() }
    }
  }
}
