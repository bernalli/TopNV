import AppKit
import TopNVCore

/// A zero-width item follows the menu bar's appearance, independently of TopNV's visible icon.
@MainActor
final class MenuBarConditionsMonitor {
  private let item: NSStatusItem
  private var observation: NSKeyValueObservation?
  var onChange: (() -> Void)?

  init() {
    item = NSStatusBar.system.statusItem(withLength: 0)
    item.button?.setAccessibilityElement(false)
    observation = item.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
      MainActor.assumeIsolated { self?.onChange?() }
    }
  }

  func appearance(on screen: NSScreen) -> KeyedOverlayState.Appearance {
    // A probe supplies evidence only for its own display. Never reuse its light appearance
    // on another display whose wallpaper/menu bar may be dark.
    guard let button = item.button, button.window?.screen == screen else { return .unknown }
    switch button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark]) {
    case .aqua?, .vibrantLight?: return .light
    case .darkAqua?, .vibrantDark?: return .dark
    default: return .unknown
    }
  }

  func stop() {
    observation = nil
    onChange = nil
    NSStatusBar.system.removeStatusItem(item)
  }
}
