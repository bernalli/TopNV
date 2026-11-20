import AppKit
import QuartzCore
import TopNVCore

@MainActor
protocol BarSampling: AnyObject {
  var onSample: (() -> Void)? { get set }
  func sampleNow() -> BarSample
  func monitorAppearance(_ enabled: Bool)
  func scheduleSamples(needed: Bool, duringReveal: Bool)
}

@MainActor
final class BarSampler: BarSampling {
  var onSample: (() -> Void)?
  private var monitor: MenuBarConditionsMonitor?
  private var timer: Timer?
  private var dock: NSRunningApplication?

  func monitorAppearance(_ enabled: Bool) {
    if enabled && monitor == nil {
      monitor = MenuBarConditionsMonitor()
      monitor?.onChange = { [weak self] in self?.onSample?() }
    } else if !enabled {
      monitor?.stop()
      monitor = nil
    }
  }

  static func interval(duringReveal: Bool) -> Double { duringReveal ? 1.0 / 30 : 0.1 }
  static func tolerance(duringReveal: Bool) -> Double { duringReveal ? 0.002 : 0.02 }

  func scheduleSamples(needed: Bool, duringReveal: Bool) {
    guard needed else {
      timer?.invalidate()
      timer = nil
      return
    }
    let interval = Self.interval(duringReveal: duringReveal)
    guard timer?.timeInterval != interval else { return }
    timer?.invalidate()
    let timer = Timer(fire: Date(timeIntervalSinceNow: interval), interval: interval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.onSample?() }
    }
    timer.tolerance = Self.tolerance(duringReveal: duringReveal)
    self.timer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func sampleNow() -> BarSample {
    let screens = NSScreen.screens
    let windows = screens.first.flatMap { primary -> [MenuBarEvidence.Window]? in
      guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
              as? [[String: Any]] else { return nil }
      if dock == nil || dock?.isTerminated == true {
        dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
      }
      return MenuBarEvidence.windows(from: list, ownPID: ProcessInfo.processInfo.processIdentifier,
                                     frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                     primaryScreenHeight: primary.frame.maxY, dockPID: dock?.processIdentifier)
    }
    var appearance: [UInt32: KeyedOverlayState.Appearance] = [:]
    let displays = screens.compactMap { screen -> BarDisplay? in
      guard let display = BarDisplay(screen: screen), appearance[display.id] == nil else { return nil }
      appearance[display.id] = monitor?.appearance(on: screen) ?? .unknown
      return display
    }
    return .init(displays: displays, windows: windows,
                 systemFullScreen: NSApp.currentSystemPresentationOptions.contains(.fullScreen),
                 appearance: appearance, activeKeyWindows: [:], now: ProcessInfo.processInfo.systemUptime,
                 reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                 signalTime: CACurrentMediaTime())
  }
}
