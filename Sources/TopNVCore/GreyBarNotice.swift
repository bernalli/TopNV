import Foundation

/// The appearance macOS gives to the menu bar, as a status item button reports it.
public enum MenuBarAppearance: Sendable {
  case light, dark
}

/// What decides whether the menu bar looks grey over the black band.
public struct MenuBarConditions: Equatable, Sendable {
  /// Nil when the app cannot read it.
  public var appearance: MenuBarAppearance?
  public var hidesNotch: Bool
  public var hasNotch: Bool
  public var isBandOnScreen: Bool

  public init(
    appearance: MenuBarAppearance?, hidesNotch: Bool, hasNotch: Bool, isBandOnScreen: Bool
  ) {
    self.appearance = appearance
    self.hidesNotch = hidesNotch
    self.hasNotch = hasNotch
    self.isBandOnScreen = isBandOnScreen
  }

  /// macOS chose a light menu bar before the band was there, so it draws a light backdrop on
  /// top of the band and the bar looks grey instead of black.
  public var isGrey: Bool {
    appearance == .light && hidesNotch && hasNotch && isBandOnScreen
  }
}

/// Reports the menu bar and the band. The app reads AppKit; the tests use a fake.
@MainActor
public protocol MenuBarConditionsSource: AnyObject {
  var conditions: MenuBarConditions { get }
  /// Called after any of the conditions may have changed.
  var onChange: (@MainActor () -> Void)? { get set }
}

public enum GreyBarNoticeAnswer: Sendable {
  case openSettings, notNow
}

/// Shows the notice about the grey menu bar at most once per launch, after the bar has been
/// grey for `delay`, and never while the first-launch update question is on screen.
@MainActor
public final class GreyBarNoticeCoordinator {
  /// macOS rebuilds the menu bar at wallpaper and Space changes; wait until it settles.
  public static let delay: Duration = .seconds(2)
  public static let wallpaperSettingsURL = URL(
    string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")
  public static let systemSettingsBundleIdentifier = "com.apple.systempreferences"

  /// Runs an action after a delay; the returned closure cancels it.
  public typealias Schedule = @MainActor (Duration, @escaping @MainActor () -> Void) -> () -> Void

  private enum State { case waiting, queued, shown }

  private let source: MenuBarConditionsSource
  private let schedule: Schedule
  private let isQuestionOnScreen: @MainActor () -> Bool
  private let show: @MainActor (@escaping (GreyBarNoticeAnswer) -> Void) -> Void
  private var state = State.waiting
  private var cancelPending: (() -> Void)?
  public private(set) var answer: GreyBarNoticeAnswer?

  public init(
    source: MenuBarConditionsSource, schedule: @escaping Schedule = sleepSchedule,
    isQuestionOnScreen: @escaping @MainActor () -> Bool,
    show: @escaping @MainActor (@escaping (GreyBarNoticeAnswer) -> Void) -> Void
  ) {
    self.source = source
    self.schedule = schedule
    self.isQuestionOnScreen = isQuestionOnScreen
    self.show = show
  }

  public func start() {
    source.onChange = { [weak self] in self?.conditionsDidChange() }
    conditionsDidChange()
  }

  /// Called after the first-launch question closed: a waiting notice is shown now, if the bar
  /// is still grey.
  public func questionDidClose() {
    guard state == .queued else { return }
    state = .waiting
    if source.conditions.isGrey { present() }
  }

  private func conditionsDidChange() {
    let isGrey = source.conditions.isGrey
    switch state {
    case .shown:
      return
    case .queued:
      if !isGrey { state = .waiting }
    case .waiting:
      if !isGrey {
        cancelPending?()
        cancelPending = nil
      } else if cancelPending == nil {
        cancelPending = schedule(Self.delay) { [weak self] in self?.delayDidPass() }
      }
    }
  }

  private func delayDidPass() {
    cancelPending = nil
    // The band can go away without a report, so the state is read again.
    guard state == .waiting, source.conditions.isGrey else { return }
    if isQuestionOnScreen() {
      state = .queued
    } else {
      present()
    }
  }

  private func present() {
    state = .shown
    show { [weak self] answer in
      guard let self, self.answer == nil else { return }
      self.answer = answer
    }
  }

  /// Opens the Wallpaper pane, or System Settings when the pane does not open.
  public static func openWallpaperSettings(
    open: (URL) -> Bool, systemSettings: () -> URL?
  ) -> Bool {
    if let url = wallpaperSettingsURL, open(url) { return true }
    guard let application = systemSettings() else { return false }
    return open(application)
  }

  public static func sleepSchedule(
    _ delay: Duration, _ action: @escaping @MainActor () -> Void
  ) -> () -> Void {
    let task = Task { @MainActor in
      do {
        try await Task.sleep(for: delay)
      } catch {
        return  // Cancelled.
      }
      action()
    }
    return { task.cancel() }
  }
}
