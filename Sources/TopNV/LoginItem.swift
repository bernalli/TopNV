import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` so the menu can show and change the launch-at-login state.
@MainActor
final class LoginItem: ObservableObject {
  /// True when the app is registered as a login item (enabled or waiting for approval).
  @Published private(set) var isEnabled = false
  /// True when the user still has to allow the app in System Settings.
  @Published private(set) var needsApproval = false
  /// The last registration error, shown in Options until the next successful change.
  @Published private(set) var errorMessage: String?

  init() {
    refresh()
  }

  func refresh() {
    let status = SMAppService.mainApp.status
    isEnabled = status == .enabled || status == .requiresApproval
    needsApproval = status == .requiresApproval
  }

  func setEnabled(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
    refresh()
  }
}
