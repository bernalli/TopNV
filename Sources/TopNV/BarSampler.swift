import AppKit
import QuartzCore
import TopNVCore

@MainActor
protocol BarSampling: AnyObject {
  var onSample: (() -> Void)? { get set }
  func sampleNow() -> BarSample
  func monitorAppearance(_ enabled: Bool)
  func scheduleSamples(needed: Bool, duringReveal: Bool)
  /// A rebuild or screen event makes earlier window list reads stale.
  func discardPending()
}

extension BarSampling {
  func discardPending() {}
}

/// What a window list read needs from the main thread. Every field is a plain value.
struct WindowListQuery: Sendable {
  let ownPID: Int32
  let frontmostPID: Int32?
  let primaryScreenHeight: CGFloat
  let dockPID: Int32?
}

/// One window list and the time it was acquired.
struct WindowListRead: Sendable {
  let windows: [MenuBarEvidence.Window]?
  let signalTime: Double
  let uptime: Double
}

typealias WindowListReader = @Sendable (WindowListQuery?) -> WindowListRead

@MainActor
final class BarSampler: BarSampling {
  var onSample: (() -> Void)?
  private var backgroundPreference = MenuBarBackgroundPreference()
  private var monitor: MenuBarConditionsMonitor?
  private var timer: Timer?
  private var dock: NSRunningApplication?
  private let reader: WindowListReader
  private let makeSample: ((WindowListRead) -> BarSample)?
  private let installTimer: (Timer) -> Void
  /// Timer samples read the window list off the main thread: during a reveal or a return the read
  /// can block for longer than a display frame, and the entrance is drawn on the main thread.
  private let queue = DispatchQueue(label: "TopNV.WindowList", qos: .userInteractive)
  private var reading = false
  private var recoveryRequested = false
  private var generation: UInt64 = 0
  /// Shared by direct reads and reads consumed through the callback.
  private var lastSampleTime = -Double.infinity
  /// The read that `onSample` delivers. Only the first `sampleNow()` inside `onSample` uses it.
  private var delivered: WindowListRead?

  init(reader: @escaping WindowListReader = { BarSampler.readWindowList($0) },
       makeSample: ((WindowListRead) -> BarSample)? = nil,
       installTimer: @escaping (Timer) -> Void = { RunLoop.main.add($0, forMode: .common) }) {
    self.reader = reader
    self.makeSample = makeSample
    self.installTimer = installTimer
  }

  /// Safe on any thread: the window list functions of Quartz do not need the main thread.
  nonisolated static func readWindowList(_ query: WindowListQuery?) -> WindowListRead {
    let windows = query.flatMap { query -> [MenuBarEvidence.Window]? in
      guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
              as? [[String: Any]] else { return nil }
      return MenuBarEvidence.windows(from: list, ownPID: query.ownPID, frontmostPID: query.frontmostPID,
                                     primaryScreenHeight: query.primaryScreenHeight, dockPID: query.dockPID)
    }
    return WindowListRead(windows: windows, signalTime: CACurrentMediaTime(),
                          uptime: ProcessInfo.processInfo.systemUptime)
  }

  func monitorAppearance(_ enabled: Bool) {
    guard makeSample == nil else { return }
    if enabled && monitor == nil {
      monitor = MenuBarConditionsMonitor()
      monitor?.onChange = { [weak self] in self?.requestSample() }
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
      recoveryRequested = false
      discardPending()
      return
    }
    let interval = Self.interval(duringReveal: duringReveal)
    guard timer?.timeInterval != interval else { return }
    timer?.invalidate()
    let timer = Timer(fire: Date(timeIntervalSinceNow: interval), interval: interval, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.requestSample() }
    }
    timer.tolerance = Self.tolerance(duringReveal: duringReveal)
    self.timer = timer
    installTimer(timer)
  }

  /// Keep at most one async read in flight and coalesce requests for a fresh read behind it.
  func requestSample() {
    guard !reading else {
      recoveryRequested = true
      return
    }
    reading = true
    let started = generation
    let query = query()
    let reader = reader
    queue.async { [weak self] in
      let read = reader(query)
      DispatchQueue.main.async {
        MainActor.assumeIsolated { self?.deliver(read, generation: started) }
      }
    }
  }

  private func deliver(_ read: WindowListRead, generation started: UInt64) {
    defer {
      delivered = nil
      reading = false
      if recoveryRequested {
        recoveryRequested = false
        requestSample()
      }
    }
    guard started == generation, read.signalTime > lastSampleTime else { return }
    delivered = read
    onSample?()
  }

  func discardPending() {
    generation &+= 1
    delivered = nil
  }

  /// Uses the delivered read inside `onSample`; every other caller reads synchronously.
  func sampleNow() -> BarSample {
    let read = delivered ?? reader(query())
    delivered = nil
    lastSampleTime = max(lastSampleTime, read.signalTime)
    if let makeSample { return makeSample(read) }
    var appearance: [UInt32: KeyedOverlayState.Appearance] = [:]
    let displays = NSScreen.screens.compactMap { screen -> BarDisplay? in
      guard let display = BarDisplay(screen: screen), appearance[display.id] == nil else { return nil }
      appearance[display.id] = monitor?.appearance(on: screen) ?? .unknown
      return display
    }
    return .init(displays: displays, windows: read.windows,
                 systemFullScreen: NSApp.currentSystemPresentationOptions.contains(.fullScreen),
                 appearance: appearance, activeKeyWindows: [:], now: read.uptime,
                 reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                 signalTime: read.signalTime, menuBarBackground: backgroundPreference.value(at: read.uptime))
  }

  private func query() -> WindowListQuery? {
    guard let primary = NSScreen.screens.first else { return nil }
    if dock == nil || dock?.isTerminated == true {
      dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
    }
    return WindowListQuery(ownPID: ProcessInfo.processInfo.processIdentifier,
                           frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                           primaryScreenHeight: primary.frame.maxY, dockPID: dock?.processIdentifier)
  }
}
