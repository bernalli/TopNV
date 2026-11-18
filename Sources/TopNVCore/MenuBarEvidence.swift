import CoreGraphics
import Foundation

/// Public, title-free window metadata. All rectangles use AppKit's global coordinates.
/// Public metadata cannot tell a zoomed desktop window from a full-screen window that stays
/// below the camera housing: with the Dock hidden or at a side both have the same bounds. That
/// full-screen layout shows a black strip, which the appearance gate reports as dark, so only
/// a window that reaches the top edge is taken as evidence here.
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
    public init(owner: Owner, layer: Int, bounds: CGRect, isWindowManager: Bool = false) {
      self.owner = owner
      self.layer = layer
      self.bounds = bounds
      self.isWindowManager = isWindowManager
    }
  }

  public struct Result {
    public let context: KeyedOverlayState.Context
    public let menuVisible: Bool
    /// Show Desktop or a click on the wallpaper: the backdrop under the menu bar is darker.
    public let desktopRevealed: Bool
  }

  /// Converts the dictionaries of `CGWindowListCopyWindowInfo`. Window titles are never read.
  /// A window without a usable owner PID, layer or bounds makes the whole list unavailable:
  /// incomplete evidence is never permission to create. A window without an owner name is a
  /// plain application window, which can only suppress the effect.
  public static func windows(from list: [[String: Any]], ownPID: Int32,
                             primaryScreenHeight: CGFloat) -> [Window]? {
    guard primaryScreenHeight.isFinite, primaryScreenHeight > 0 else { return nil }
    var result: [Window] = []
    result.reserveCapacity(list.count)
    for info in list {
      // The four numbers are read one by one: `CGRect(dictionaryRepresentation:)` raises an
      // Objective-C exception, which Swift cannot catch, when a value is not a number.
      guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
            let dictionary = info[kCGWindowBounds as String] as? [String: Any],
            let x = (dictionary["X"] as? NSNumber)?.doubleValue,
            let y = (dictionary["Y"] as? NSNumber)?.doubleValue,
            let width = (dictionary["Width"] as? NSNumber)?.doubleValue,
            let height = (dictionary["Height"] as? NSNumber)?.doubleValue,
            [x, y, width, height].allSatisfy(\.isFinite) else {
        return nil
      }
      let rect = CGRect(x: x, y: y, width: width, height: height)
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
      result.append(Window(owner: owner, layer: layer,
                           bounds: CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY,
                                          width: rect.width, height: rect.height),
                           isWindowManager: pid != ownPID && name == "WindowManager"))
    }
    return result
  }

  public static func evaluate(frame: CGRect, visibleFrame: CGRect, bandFrame: CGRect,
                              windows: [Window]?) -> Result {
    guard let windows, valid(frame), valid(visibleFrame), valid(bandFrame),
          frame.contains(visibleFrame), frame.contains(bandFrame) else {
      return Result(context: .unknown, menuVisible: false, desktopRevealed: false)
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
    let noReservedTop = visibleFrame.maxY >= frame.maxY - tolerance
    // Show Desktop and a click on the wallpaper add a WindowManager window from the bottom edge
    // to the top edge. The WindowManager windows at negative layers are always there: they are
    // the desktop itself. Small WindowManager windows at positive layers do not darken the bar.
    let desktopRevealed = windows.contains {
      $0.isWindowManager && $0.layer >= 0 && valid($0.bounds)
        && $0.bounds.intersection(frame).width >= frame.width * 0.9
        && $0.bounds.minY <= frame.minY + tolerance
        && $0.bounds.maxY >= frame.maxY - tolerance
    }
    return Result(context: coveringApp || noReservedTop ? .fullScreen : .desktop,
                  menuVisible: menuVisible, desktopRevealed: desktopRevealed)
  }

  private static func valid(_ rect: CGRect) -> Bool {
    !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0
      && [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
  }
}
