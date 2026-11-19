import CoreFoundation
import CoreGraphics
import Foundation

/// Public, title-free window metadata. All rectangles use AppKit's global coordinates.
public enum MenuBarEvidence {
  public enum Owner { case windowServer, desktop, ownApp, application }

  /// The level of the keyed window. A window above it is drawn over the effect.
  public static let overlayLevel = 26
  /// One level above the desktop level. See `Result.fullScreenBackdrop`.
  public static let fullScreenBackdropLayer = Int(CGWindowLevelForKey(.desktopWindow)) + 1

  public struct Window {
    public let owner: Owner
    public let number: CGWindowID?
    public let layer: Int
    public let bounds: CGRect
    /// Owned by `WindowManager`. Such a window is also a `.desktop` window, never evidence of a
    /// full-screen app; at a layer of zero or more it can reveal the desktop.
    let isDock: Bool
    public let isWindowManager: Bool
    public let isFrontmostApp: Bool
    public let alpha: Double

    public init(owner: Owner, layer: Int, bounds: CGRect, isWindowManager: Bool = false,
                alpha: Double = 1, isFrontmostApp: Bool = false, number: CGWindowID? = nil, isDock: Bool = false) {
      self.isDock = isDock
      self.number = number
      self.owner = owner
      self.layer = layer
      self.bounds = bounds
      self.isWindowManager = isWindowManager
      self.alpha = alpha
      self.isFrontmostApp = isFrontmostApp
    }
  }

  public struct Result {
    fileprivate var visibleMenuBounds: CGRect?
    public var menuBounds: CGRect? { visibleMenuBounds }

    public let context: KeyedOverlayState.Context
    /// The active app is in native full screen and has a matching window on this display.
    public let nativeFullScreen: Bool
    public let menuVisible: Bool
    /// Show Desktop or a click on the wallpaper: the backdrop under the menu bar is darker.
    public var desktopRevealed: Bool { revealOverride ?? (revealSurface != nil) }
    var revealOverride: Bool?
    let revealSurface: Window?
    public var revealLayer: Int? { revealSurface?.layer }
    /// A Space switch slides the desktop of this display sideways. Every other value then mixes
    /// the Space that leaves with the Space that arrives.
    public let spaceSliding: Bool
    /// At rest a native full-screen Space has a WindowManager backdrop one level above
    /// the desktop level. This signal is local to the display.
    public let fullScreenBackdrop: Bool
    /// The base band can animate on an ordinary desktop even when the key is gated off.
    let permitsBandEntrance: Bool
  }

  /// Converts the dictionaries of `CGWindowListCopyWindowInfo`. Window titles are never read.
  /// A window without a usable owner PID, layer, bounds or alpha makes the whole list unavailable:
  /// incomplete evidence is never permission to create. A window without an owner name is a
  /// plain application window, which can only suppress the effect.
  public static func windows(from list: [[String: Any]], ownPID: Int32,
                             frontmostPID: Int32? = nil, primaryScreenHeight: CGFloat,
                             dockPID: Int32? = nil) -> [Window]? {
    guard primaryScreenHeight.isFinite, primaryScreenHeight > 0 else { return nil }
    var result: [Window] = []
    result.reserveCapacity(list.count)
    for info in list {
      // The four numbers are read one by one: `CGRect(dictionaryRepresentation:)` raises an
      // Objective-C exception, which Swift cannot catch, when a value is not a number.
      guard let pidValue = finiteNumber(info[kCGWindowOwnerPID as String]),
            let pid = Int32(exactly: pidValue), pid > 0,
            let layerValue = finiteNumber(info[kCGWindowLayer as String]),
            let layer = Int32(exactly: layerValue),
            let alpha = finiteNumber(info[kCGWindowAlpha as String]), (0...1).contains(alpha),
            let dictionary = info[kCGWindowBounds as String] as? [String: Any],
            let x = finiteNumber(dictionary["X"]),
            let y = finiteNumber(dictionary["Y"]),
            let width = finiteNumber(dictionary["Width"]), width >= 0,
            let height = finiteNumber(dictionary["Height"]), height >= 0 else { return nil }
      let top = y + height
      let minY = Double(primaryScreenHeight) - top
      let maxY = Double(primaryScreenHeight) - y
      guard [x + width, top, minY, maxY].allSatisfy(\.isFinite) else { return nil }
      let name: String?
      switch info[kCGWindowOwnerName as String] {
      case nil: name = nil
      case let value as String: name = value
      default: return nil
      }
      let isDock = pid == dockPID || name == "Dock"
      let owner: Owner
      if pid == ownPID {
        owner = .ownApp
      } else if name == "Window Server" {
        owner = .windowServer
      } else if isDock || name == "WindowManager" || name == "Screenshot"
                  || (name == "Finder" && layer < 0) {
        // Show Desktop and a click on the wallpaper add a full-screen WindowManager window at
        // layer 18, and the screenshot and recording tool a full-screen Screenshot window at
        // layer 24. Neither is a full-screen app: taken as evidence they turn the band off.
        owner = .desktop
      } else {
        owner = .application
      }
      // Quartz measures from the top of the primary screen, AppKit from its bottom.
      result.append(Window(owner: owner, layer: Int(layer),
                           bounds: CGRect(x: x, y: minY, width: width, height: height),
                           isWindowManager: pid != ownPID && name == "WindowManager", alpha: alpha,
                           isFrontmostApp: owner == .application && pid == frontmostPID,
                           number: finiteNumber(info[kCGWindowNumber as String]).flatMap(CGWindowID.init(exactly:)),
                           isDock: owner == .desktop && isDock))
    }
    return result
  }

  /// A Window Server window along the top edge, as wide as the band.
  /// The system layer can vary between macOS versions.
  public static func menuSurface(in windows: [Window], bandFrame: CGRect, preferredLayer: Int? = nil) -> Window? {
    let tolerance: CGFloat = 2
    let matches = windows.lazy.filter {
      $0.owner == .windowServer && $0.layer >= 0 && valid($0.bounds)
        && $0.bounds.minX <= bandFrame.minX + tolerance
        && $0.bounds.maxX >= bandFrame.maxX - tolerance
        && abs($0.bounds.maxY - bandFrame.maxY) <= tolerance
        && $0.bounds.height <= bandFrame.height * 2
    }
    guard let preferredLayer else { return matches.first }
    return matches.first { $0.layer == preferredLayer } ?? matches.first
  }

  public static func evaluate(frame: CGRect, visibleFrame: CGRect, bandFrame: CGRect,
                              windows: [Window]?, systemFullScreen: Bool = false,
                              displayFrames: [CGRect] = []) -> Result {
    guard let windows, valid(frame), valid(visibleFrame), valid(bandFrame),
          frame.contains(visibleFrame), frame.contains(bandFrame) else {
      return Result(context: .unknown, nativeFullScreen: false, menuVisible: false, revealSurface: nil,
                    spaceSliding: false, fullScreenBackdrop: false, permitsBandEntrance: false)
    }
    let tolerance: CGFloat = 2
    let menuVisible = menuSurface(in: windows, bandFrame: bandFrame) != nil
    // A window from the bottom edge to the top edge lies under the keyed strip: a full-screen
    // app that uses the camera-housing area, or a borderless full-screen window on a desktop.
    // Partial-width windows cover Split View. Our own band and corners, the desktop, the Dock
    // and windows above the keyed level are not evidence.
    let coveringApp = windows.contains {
      $0.owner == .application && (0...overlayLevel).contains($0.layer) && valid($0.bounds)
        && $0.bounds.intersection(frame).width >= frame.width * 0.4
        && $0.bounds.minY <= frame.minY + tolerance
        && $0.bounds.maxY >= bandFrame.maxY - tolerance
    }
    // Native full screen can split one app into several surfaces below the camera housing.
    // A zoomed desktop window with a hidden Dock can reach the same bottom edge.
    let nativeFullScreen = systemFullScreen && windows.contains {
      $0.isFrontmostApp && $0.owner == .application && $0.layer == 0 && $0.alpha > 0 && valid($0.bounds)
        && abs($0.bounds.minY - frame.minY) <= tolerance
        && $0.bounds.intersection(frame).height > 0
        && $0.bounds.intersection(frame).width >= frame.width * 0.4
    }
    let noReservedTop = visibleFrame.maxY >= frame.maxY - tolerance
    let revealSurface = revealSurface(in: windows, frame: frame, tolerance: tolerance)
    // The windows bound to a Space slide with it: the desktop window of WindowManager (negative
    // layer, as large as the display) and our keyed windows. One of them displaced sideways and
    // still over the display is a Space switch in progress. The menu bar slides too.
    let spaceSliding = windows.contains {
      let bound = isSpaceBackground($0, frame: frame, tolerance: tolerance)
        || ($0.owner == .ownApp && $0.layer == overlayLevel
              && sameSize($0.bounds, bandFrame, tolerance))
      return bound && valid($0.bounds)
        && abs($0.bounds.minX - frame.minX) > tolerance
        && abs($0.bounds.maxY - frame.maxY) <= tolerance
        && $0.bounds.intersection(frame).width > tolerance
    }
    let backdrop = fullScreenBackdrop(frame: frame, windows: windows, tolerance)
    let fullScreenApp = nativeFullScreen || coveringApp
    let autoHiddenMenu = noReservedTop && autoHiddenDesktop(frame, windows, displayFrames, systemFullScreen, tolerance)
    let reservedMenu = !noReservedTop && (menuVisible || (revealSurface != nil && !systemFullScreen))
    let permitsBandEntrance = !fullScreenApp && !backdrop && !spaceSliding && (reservedMenu || autoHiddenMenu)
    // A transition can list several menu surfaces. The cover starts below their lowest edge.
    // Prefer stationary surfaces at the system menu level when that level is present.
    let menuLayer = Int(CGWindowLevelForKey(.mainMenuWindow))
    let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
    let candidates = windows.lazy.filter {
      $0.owner == .windowServer && ($0.layer == menuLayer || $0.layer == statusLayer)
        && $0.alpha > 0 && valid($0.bounds)
        && $0.bounds.maxY == frame.maxY && $0.bounds.minX == frame.minX && $0.bounds.width == frame.width
        && $0.bounds.height <= bandFrame.height * 2
    }
    let lowerEdge: (Window, Window) -> Bool = { $0.bounds.minY < $1.bounds.minY }
    let bounds = (candidates.filter { $0.layer == menuLayer }.min(by: lowerEdge)
      ?? candidates.min(by: lowerEdge))?.bounds
    return Result(visibleMenuBounds: bounds, context: fullScreenApp || noReservedTop ? .fullScreen : .desktop,
                  nativeFullScreen: nativeFullScreen,
                  menuVisible: menuVisible, revealSurface: revealSurface,
                  spaceSliding: spaceSliding, fullScreenBackdrop: backdrop, permitsBandEntrance: permitsBandEntrance)
  }

  private static func revealSurface(in windows: [Window], frame: CGRect, tolerance: CGFloat) -> Window? {
    func coversDisplay(_ window: Window) -> Bool {
      valid(window.bounds) && window.alpha > 0 && window.alpha <= 1
        && window.bounds.intersection(frame).width >= frame.width * 0.9
        && window.bounds.minY <= frame.minY + tolerance && window.bounds.maxY >= frame.maxY - tolerance
    }
    if let surface = windows.first(where: { $0.isWindowManager && $0.layer >= 0 && coversDisplay($0) }) {
      return surface
    }
    // On older systems Dock hosts the overview. A lone layer-20 Dock is ordinary;
    // App Exposé has no excess of layer-20 surfaces over layer-18 surfaces.
    guard let overview = windows.first(where: { $0.isDock && $0.layer == 18 && coversDisplay($0) }) else { return nil }
    let dock = windows.filter { $0.isDock && $0.alpha > 0 && $0.bounds.intersects(frame) }
    return dock.filter { $0.layer == 20 }.count > dock.filter { $0.layer == 18 }.count ? overview : nil
  }

  private static func isSpaceBackground(_ window: Window, frame: CGRect, tolerance: CGFloat) -> Bool {
    window.isWindowManager && window.layer < 0 && window.alpha > 0 && sameSize(window.bounds, frame, tolerance)
  }

  private static func stationaryBackground(_ windows: [Window], _ frame: CGRect, _ tolerance: CGFloat) -> Bool {
    windows.contains {
      isSpaceBackground($0, frame: frame, tolerance: tolerance) && valid($0.bounds)
        && abs($0.bounds.minX - frame.minX) <= tolerance
        && abs($0.bounds.minY - frame.minY) <= tolerance
    }
  }

  /// A stationary Space background can prove a desktop with an auto-hidden menu.
  /// A system fullscreen signal requires evidence that attributes it to another display.
  private static func autoHiddenDesktop(_ frame: CGRect, _ windows: [Window], _ displayFrames: [CGRect],
                                        _ systemFullScreen: Bool, _ tolerance: CGFloat) -> Bool {
    guard stationaryBackground(windows, frame, tolerance) else { return false }
    return !systemFullScreen || displayFrames.contains {
      $0 != frame && fullScreenBackdrop(frame: $0, windows: windows, tolerance)
    }
  }

  private static func fullScreenBackdrop(frame: CGRect, windows: [Window], _ tolerance: CGFloat) -> Bool {
    windows.contains {
      $0.isWindowManager && $0.layer == fullScreenBackdropLayer && $0.alpha > 0 && valid($0.bounds)
        && sameSize($0.bounds, frame, tolerance)
        && abs($0.bounds.minX - frame.minX) <= tolerance
        && abs($0.bounds.minY - frame.minY) <= tolerance
    }
  }

  private static func sameSize(_ a: CGRect, _ b: CGRect, _ tolerance: CGFloat) -> Bool {
    abs(a.size.width - b.size.width) <= tolerance && abs(a.size.height - b.size.height) <= tolerance
  }

  private static func finiteNumber(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFNumberGetTypeID() else { return nil }
    let converted = number.doubleValue
    return converted.isFinite ? converted : nil
  }

  private static func valid(_ rect: CGRect) -> Bool {
    !rect.isNull && !rect.isInfinite && rect.size.width > 0 && rect.size.height > 0
      && [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
  }
}
