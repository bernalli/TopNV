import AppKit
import BackdropRuntime
import TopNVCore
import os

/// Opt-in test on a normal desktop. The marker belongs to the test bundle's defaults domain.
@MainActor final class SystemDarkMenuBarProbe {
  private static let marker = "systemDarkMenuBarRestorePending"
  nonisolated private static let logger = Logger(subsystem: "TopNV", category: "SystemDarkMenuBar")
  nonisolated private static let runLoopModes: [RunLoop.Mode] = [.common, .modalPanel]
  private let defaults: UserDefaults
  private let client: SystemDarkMenuBarClient?
  private var state: SystemDarkMenuBarState
  private var timeouts: [Int: Timer] = [:]
  private weak var button: NSStatusBarButton?
  private var observation: NSKeyValueObservation?
  private var onChange: (() -> Void)?

  init?(bundleIdentifier: String?, defaults: UserDefaults = .standard) {
    guard let state = SystemDarkMenuBarState(bundleIdentifier: bundleIdentifier,
                                             saved: defaults.object(forKey: Self.marker)) else { return nil }
    self.defaults = defaults
    self.state = state
    client = SystemDarkMenuBarClient.resolve()
    if client == nil {
      Self.logger.error("System menu bar appearance request unavailable. Test disabled.")
    }
  }

  var suspendsKey: Bool { client != nil && state.suspendsKey }

  func attach(to menu: StatusMenuController, overlay: OverlayController) {
    menu.darkMenuBarProbe = self
    onChange = { [weak self, weak overlay, weak menu] in
      overlay?.suspendMenuBarKey = self?.suspendsKey == true
      menu?.refresh()
    }
    start(button: menu.statusItem.button)
    menu.refresh()
  }

  private func start(button: NSStatusBarButton?) {
    self.button = button
    guard client != nil else { return }
    observation = button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
      MainActor.assumeIsolated {
        if self?.suspendsKey == true { self?.logAppearance() }
      }
    }
    apply(state.start())
  }

  func toggle() {
    guard client != nil else { return }
    apply(state.toggle())
  }

  func insertRow(in rows: inout [MenuRow]) {
    let row = state.menuRow(clientAvailable: client != nil)
    rows.insert(row, at: rows.firstIndex { $0.id == "separator.app" } ?? rows.endIndex)
  }

  /// Keeps the client alive for restoration. An unanswered restore cancels an ordinary Quit.
  func terminationReply(to application: NSApplication) -> NSApplication.TerminateReply {
    guard client != nil, state.needsRestore else { return .terminateNow }
    let effects = state.quit()
    // AppKit must receive the delegate's reply before completing a deferred Quit.
    RunLoop.main.perform(inModes: Self.runLoopModes) { [weak self] in
      MainActor.assumeIsolated { self?.apply(effects) }
    }
    CFRunLoopWakeUp(CFRunLoopGetMain())
    return .terminateLater
  }

  func willTerminate() {
    guard state.needsRestore, let client else { return }
    // A termination path that bypasses the delegate reply can only make a best-effort
    // request here. The marker stays intact so launch can retry.
    Self.logger.info("Requesting fallback restore at termination")
    client.request(false) { error in
      Self.logger.info("Fallback restore result=\(error ?? "ok", privacy: .public)")
    }
  }

  private func apply(_ effects: [SystemDarkMenuBarState.Effect]) {
    onChange?()
    logAppearance()
    for effect in effects {
      switch effect {
      case .send(let request): send(request)
      case .clearMarker:
        defaults.removeObject(forKey: Self.marker)
        defaults.synchronize()
      case .finishQuit(let allowed):
        // A test copy must always quit. The marker stays, so the next launch retries the restore.
        if !allowed { Self.logger.error("Quitting with system menu bar restoration still pending") }
        NSApp.reply(toApplicationShouldTerminate: true)
      }
    }
  }

  private func send(_ request: SystemDarkMenuBarState.Request) {
    guard let client else { return }
    if request.enabled {
      // Write ahead of IPC so an interrupted launch can undo even an unacknowledged request.
      defaults.set(true, forKey: Self.marker)
      guard defaults.synchronize() else {
        Self.logger.error("Could not persist the restore marker. Skipping enable.")
        apply(state.complete(request, reply: .notSent))
        return
      }
    }
    let timer = Timer(timeInterval: 2, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.timeouts[request.id] = nil
        Self.logger.error("Request \(request.id) timed out: enabled=\(request.enabled)")
        self.apply(self.state.timeout(request))
      }
    }
    timeouts[request.id] = timer
    for mode in Self.runLoopModes { RunLoop.main.add(timer, forMode: mode) }
    Self.logger.info("Request \(request.id): enabled=\(request.enabled)")
    client.request(request.enabled) { [weak self] error in
      Self.logger.info("Reply \(request.id): enabled=\(request.enabled), result=\(error ?? "ok", privacy: .public)")
      RunLoop.main.perform(inModes: Self.runLoopModes) {
        MainActor.assumeIsolated {
          guard let self else { return }
          self.timeouts.removeValue(forKey: request.id)?.invalidate()
          self.apply(self.state.complete(request, reply: error == nil ? .applied : .uncertain))
        }
      }
      CFRunLoopWakeUp(CFRunLoopGetMain())
    }
  }

  private func logAppearance() {
    let item = button?.window?.screen == nil ? nil : button?.effectiveAppearance.name.rawValue
    let app = NSApp.effectiveAppearance.name.rawValue
    Self.logger.info("Status item appearance=\(item ?? "unavailable", privacy: .public), app=\(app, privacy: .public)")
  }
}
