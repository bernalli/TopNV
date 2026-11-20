import AppKit
import TopNVCore
import os

/// A test-copy light behind the menu material. KeyExecutor owns its lifetime and transaction.
@MainActor
final class KeyLamp {
  static let shared = KeyLamp(
    enabled: { RelativeMenuBarKey.shared.lampMode != .off },
    only: { RelativeMenuBarKey.shared.lampMode == .only },
    plate: { RelativeMenuBarKey.shared.lampPlate },
    changed: { RelativeMenuBarKey.shared.lampChanged(on: $0) })
  private static let logger = Logger(subsystem: "TopNV", category: "Lamp")
  // Just above the band (desktop + 1), still below application windows and the system menu.
  static let level = NSWindow.Level(rawValue: OverlayLevel.bar.rawValue + 1)

  private final class Window: OverlayWindow {
    var owner: Int?
    var pixels: PixelRect?
    var geometry: BarDisplay?
    var litSince: TimeInterval?
  }

  private var windows: [UInt32: Window] = [:]
  let enabled: () -> Bool
  let only: () -> Bool
  private let plate: () -> LampPlatePreset
  private let changed: (UInt32) -> Void
  private let log: (String) -> Void

  init(enabled: @escaping () -> Bool, only: @escaping () -> Bool = { false },
       plate: @escaping () -> LampPlatePreset = { .standard },
       changed: @escaping (UInt32) -> Void = { _ in }, log: ((String) -> Void)? = nil) {
    self.plate = plate
    self.changed = changed
    self.only = only
    self.enabled = enabled
    self.log = log ?? { line in KeyLamp.logger.info("\(line, privacy: .public)") }
  }

  func window(on display: UInt32) -> OverlayWindow? { windows[display] }

  func litSince(on display: UInt32) -> TimeInterval? { windows[display]?.litSince }

  func canPresent(_ plan: BarDisplayPlan) -> Bool {
    plan.kind == .desktop && plan.appearance == .light && plan.band.frame != nil && plan.band.pixels != nil
  }

  func apply(_ plan: BarDisplayPlan, display: UInt32, owner: Int, alpha: CGFloat) {
    guard let frame = plan.band.frame, let pixels = plan.band.pixels else { close(display); return }
    let window: Window
    if let existing = windows[display] {
      window = existing
    } else {
      window = Window(frame: frame, level: Self.level, isOpaque: true, behavior: OverlayBehavior.bar)
      window.backgroundColor = .white
      window.alphaValue = 0
      _ = BarStripView(in: window, color: .white)
      windows[display] = window
    }
    let changed = window.pixels != pixels || window.alphaValue != alpha
    let relit = alpha > 0 && (window.litSince == nil || window.owner != owner)
    let wentDark = alpha == 0 && window.litSince != nil
    window.geometry = plan.geometry
    window.owner = owner
    window.pixels = pixels
    if window.frame != frame { window.setFrame(frame, display: false) }
    (window.contentView as? BarStripView)?.apply(plan.key.mask, to: window)
    if window.alphaValue != alpha { window.alphaValue = alpha }
    if !window.isVisible { window.orderFrontRegardless() }
    if relit || wentDark {
      window.litSince = relit ? CACurrentMediaTime() : nil
      self.changed(display)
    }
    if changed { record(window, display: display, state: "present") }
  }

  func close(_ display: UInt32, owner: Int? = nil) {
    guard let window = windows[display], owner == nil || window.owner == owner else { return }
    windows.removeValue(forKey: display)
    window.alphaValue = 0
    window.close()
    if window.litSince != nil { changed(display) }
    record(window, display: display, state: "closed")
  }

  func presentPlate(_ bottom: KeyBottomPlate, on display: UInt32) {
    let preset = litSince(on: display) != nil && !only() ? plate() : nil
    bottom.apply(preset, log: log)
  }

  func recordState(displays: Set<UInt32>) {
    let ids = displays.union(windows.keys).union(NSScreen.screens.compactMap(\.displayID))
    let list = windows.isEmpty ? nil : CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
      as? [[String: Any]]
    for display in ids.sorted() {
      guard let window = windows[display] else {
        log("LampState display=\(display) state=absent")
        continue
      }
      let row = list?.first { ($0[kCGWindowNumber as String] as? Int) == window.windowNumber }
      let layer = (row?[kCGWindowLayer as String] as? Int).map(String.init) ?? "none"
      let onScreen = list == nil ? "unknown" : String(row != nil)
      let frame = window.geometry.flatMap { BarGeometry.pixels(window.frame, on: $0) }
      log("LampState display=\(display) window=\(window.windowNumber) isVisible=\(window.isVisible) "
          + "isOnActiveSpace=\(window.isOnActiveSpace) alphaValue=\(window.alphaValue) level=\(window.level.rawValue) "
          + "frame=\(frame?.description ?? "none") occlusionVisible=\(window.occlusionState.contains(.visible)) "
          + "onScreen=\(onScreen) kCGWindowLayer=\(layer)")
    }
  }

  private func record(_ window: Window, display: UInt32, state: String) {
    log("Lamp display=\(display) alpha=\(window.alphaValue) level=\(window.level.rawValue) "
        + "px=\(window.pixels?.description ?? "none") state=\(state)")
  }
}
