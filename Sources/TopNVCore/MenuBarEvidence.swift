import CoreFoundation
import CoreGraphics
import Foundation

/// Public, title-free window metadata. All rectangles use AppKit's global coordinates.
public enum MenuBarEvidence {
  public enum Owner { case windowServer, desktop, ownApp, application }

  /// The level of the keyed window. A window above it is drawn over the effect.
  public static let overlayLevel = 26

  public struct Window {
    public let owner: Owner
    public let layer: Int
    public let bounds: CGRect
    /// Owned by `WindowManager`. Such a window is also a `.desktop` window, never evidence of a
    /// full-screen app; at a layer of zero or more it can reveal the desktop.
    public let isWindowManager: Bool
    public let isFrontmostApp: Bool
    public let alpha: Double

    public init(owner: Owner, layer: Int, bounds: CGRect, isWindowManager: Bool = false,
                alpha: Double = 1, isFrontmostApp: Bool = false) {
      self.owner = owner
      self.layer = layer
      self.bounds = bounds
      self.isWindowManager = isWindowManager
      self.alpha = alpha
      self.isFrontmostApp = isFrontmostApp
    }
  }

  public struct Result {
    public let context: KeyedOverlayState.Context
    /// The active app is in native full screen and has a matching window on this display.
    public let nativeFullScreen: Bool
    public let menuVisible: Bool
    /// Show Desktop or a click on the wallpaper: the backdrop under the menu bar is darker.
    public let desktopRevealed: Bool
    /// A Space switch slides the desktop of this display sideways. Every other value then mixes
    /// the Space that leaves with the Space that arrives.
    public let spaceSliding: Bool
  }

  /// Converts the dictionaries of `CGWindowListCopyWindowInfo`. Window titles are never read.
  /// A window without a usable owner PID, layer, bounds or alpha makes the whole list unavailable:
  /// incomplete evidence is never permission to create. A window without an owner name is a
  /// plain application window, which can only suppress the effect.
  public static func windows(from list: [[String: Any]], ownPID: Int32,
                             frontmostPID: Int32? = nil, primaryScreenHeight: CGFloat) -> [Window]? {
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
      let owner: Owner
      if pid == ownPID {
        owner = .ownApp
      } else if name == "Window Server" {
        owner = .windowServer
      } else if name == "Dock" || name == "WindowManager" || name == "Screenshot"
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
                           isFrontmostApp: owner == .application && pid == frontmostPID))
    }
    return result
  }

  public static func evaluate(frame: CGRect, visibleFrame: CGRect, bandFrame: CGRect,
                              windows: [Window]?, systemFullScreen: Bool = false) -> Result {
    guard let windows, valid(frame), valid(visibleFrame), valid(bandFrame),
          frame.contains(visibleFrame), frame.contains(bandFrame) else {
      return Result(context: .unknown, nativeFullScreen: false, menuVisible: false, desktopRevealed: false,
                    spaceSliding: false)
    }
    let tolerance: CGFloat = 2
    // The menu bar surface: a Window Server window along the top edge, as wide as the band.
    // Its exact layer and height differ between macOS versions and are not required.
    let menuVisible = windows.contains {
      $0.owner == .windowServer && $0.layer >= 0 && valid($0.bounds)
        && $0.bounds.minX <= bandFrame.minX + tolerance
        && $0.bounds.maxX >= bandFrame.maxX - tolerance
        && abs($0.bounds.maxY - bandFrame.maxY) <= tolerance
        && $0.bounds.height <= bandFrame.height * 2
    }
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
    // Show Desktop and a click on the wallpaper add a WindowManager window from the bottom edge
    // to the top edge. The WindowManager windows at negative layers are always there: they are
    // the desktop itself. Small WindowManager windows at positive layers do not darken the bar.
    let desktopRevealed = windows.contains {
      $0.isWindowManager && $0.layer >= 0 && $0.alpha > 0 && $0.alpha <= 1 && valid($0.bounds)
        && $0.bounds.intersection(frame).width >= frame.width * 0.9
        && $0.bounds.minY <= frame.minY + tolerance
        && $0.bounds.maxY >= frame.maxY - tolerance
    }
    // The windows bound to a Space slide with it: the desktop window of WindowManager (negative
    // layer, as large as the display) and our keyed windows. One of them displaced sideways and
    // still over the display is a Space switch in progress. The menu bar slides too.
    let spaceSliding = windows.contains {
      let bound = ($0.isWindowManager && $0.layer < 0 && $0.alpha > 0
                     && sameSize($0.bounds, frame, tolerance))
        || ($0.owner == .ownApp && $0.layer == overlayLevel
              && sameSize($0.bounds, bandFrame, tolerance))
      return bound && valid($0.bounds)
        && abs($0.bounds.minX - frame.minX) > tolerance
        && abs($0.bounds.maxY - frame.maxY) <= tolerance
        && $0.bounds.intersection(frame).width > tolerance
    }
    return Result(context: nativeFullScreen || coveringApp || noReservedTop ? .fullScreen : .desktop,
                  nativeFullScreen: nativeFullScreen,
                  menuVisible: menuVisible, desktopRevealed: desktopRevealed,
                  spaceSliding: spaceSliding)
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
