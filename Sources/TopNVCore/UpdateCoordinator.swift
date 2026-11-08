import Foundation

public enum AutomaticUpdateAnswer { case enable, decline, dismissed }

@MainActor
public final class UpdateCoordinator {
  public enum State { case idle, awaitingAnswer, starting, ready, failed }
  public private(set) var state: State = .idle
  private let configuration: UpdateConfiguration
  private let updater: UpdaterControlling?
  private let defaults: UserDefaults
  private let ask: (@escaping (AutomaticUpdateAnswer) -> Void) -> Void
  private let onReady: () -> Void
  public init(configuration: UpdateConfiguration, updater: UpdaterControlling?, defaults: UserDefaults,
              ask: @escaping (@escaping (AutomaticUpdateAnswer) -> Void) -> Void,
              onReady: @escaping () -> Void = {}) {
    self.configuration=configuration; self.updater=updater; self.defaults=defaults
    self.ask=ask; self.onReady=onReady
  }
  public func start() {
    guard state == .idle else { return }
    guard configuration.isValid, let updater else { state = .failed; return }
    state = .starting // Guard reentry from setters and startup callbacks.
    if defaults.object(forKey: "automaticUpdateQuestionAsked") != nil { startUpdater(); return }
    updater.automaticallyChecksForUpdates = false
    defaults.set(true, forKey: "automaticUpdateQuestionAsked")
    state = .awaitingAnswer
    ask { [weak self] answer in self?.answer(answer) }
  }
  private func answer(_ answer: AutomaticUpdateAnswer) {
    guard state == .awaitingAnswer else { return }
    state = .starting // Consume before calling any external code.
    updater?.automaticallyChecksForUpdates = answer == .enable
    startUpdater()
  }
  private func startUpdater() {
    guard let updater else { state = .failed; return }
    do { try updater.start(); state = .ready; onReady() }
    catch { state = .failed }
  }
}
