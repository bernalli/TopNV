import AppKit
import TopNVCore

enum OverlayLevel {
  /// Right above the wallpaper and below every other window, so the system menu bar draws
  /// on top of the black bar and stays readable and clickable.
  static let bar = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
  /// Above the Dock and normal windows, below pop-up menus so menu-bar dropdowns stay uncovered.
  static let corner = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)
}

/// A borderless, click-through window that is present on every Space and never takes focus.
class OverlayWindow: NSWindow {
  init(frame: CGRect, level: NSWindow.Level, isOpaque opaque: Bool) {
    super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    isReleasedWhenClosed = false
    isOpaque = opaque
    backgroundColor = opaque ? .black : .clear
    hasShadow = false
    ignoresMouseEvents = true
    animationBehavior = .none
    isExcludedFromWindowsMenu = true
    self.level = level
    collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  // The bar must sit inside the menu-bar area; AppKit would otherwise push it below.
  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    frameRect
  }
}

/// The opaque black strip behind the menu bar of a notched screen.
final class BarWindow: OverlayWindow {
  init(frame: CGRect) {
    super.init(frame: frame, level: OverlayLevel.bar, isOpaque: true)
  }
}

/// One rounded screen corner: a black square with a quarter circle cut out of it.
final class CornerWindow: OverlayWindow {
  init(corner: ScreenCorner, frame: CGRect) {
    super.init(frame: frame, level: OverlayLevel.corner, isOpaque: false)
    contentView = CornerView(corner: corner)
  }
}

private final class CornerView: NSView {
  private let corner: ScreenCorner

  init(corner: ScreenCorner) {
    self.corner = corner
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var isOpaque: Bool { false }

  override func draw(_ dirtyRect: NSRect) {
    let side = bounds.width
    guard side > 0 else { return }
    let center = ScreenGeometry.arcCenter(for: corner, side: side)
    // Even-odd fill of square + circle leaves the quarter disc transparent.
    let path = NSBezierPath(rect: bounds)
    path.appendOval(
      in: NSRect(x: center.x - side, y: center.y - side, width: side * 2, height: side * 2))
    path.windingRule = .evenOdd
    NSColor.black.setFill()
    path.fill()
  }
}
