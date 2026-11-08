import Combine
import Foundation

/// Only visibility invalidates the menu bar scene; display and login settings stay in its content.
@MainActor
public final class MenuVisibility: ObservableObject {
  @Published public private(set) var isVisible: Bool
  private let defaults: UserDefaults
  private let key: String
  private let schedule: (@escaping @MainActor () -> Void) -> Void
  private var generation: UInt64 = 0

  public init(
    defaults: UserDefaults, key: String,
    schedule: @escaping (@escaping @MainActor () -> Void) -> Void = { action in
      Task { @MainActor in action() }
    }
  ) {
    self.defaults = defaults
    self.key = key
    self.schedule = schedule
    isVisible = defaults.object(forKey: key) as? Bool ?? true
  }

  /// SwiftUI can write isInserted back during a scene update. Defer publication to avoid
  /// re-entering that update; a newer request or explicit reopen supersedes pending work.
  public func requestMenuVisible(_ visible: Bool) {
    generation &+= 1
    let requestedGeneration = generation
    guard visible != isVisible else { return }
    schedule { [weak self] in
      guard let self, self.generation == requestedGeneration else { return }
      self.setMenuVisible(visible)
    }
  }

  public func setMenuVisible(_ visible: Bool) {
    generation &+= 1
    guard visible != isVisible else { return }
    isVisible = visible
    defaults.set(visible, forKey: key)
  }
}
