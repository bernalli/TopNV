import CoreGraphics

/// Public, title-free window metadata. All rectangles use AppKit's global coordinates.
/// This deliberately errs on the side of suppressing the effect: public metadata cannot
/// distinguish every maximized desktop window from a full-screen Space.
public enum MenuBarEvidence {
  public enum Owner { case windowServer, desktop, ownApp, application }

  public struct Window {
    public let owner: Owner
    public let layer: Int
    public let bounds: CGRect
    public init(owner: Owner, layer: Int, bounds: CGRect) {
      self.owner = owner
      self.layer = layer
      self.bounds = bounds
    }
  }

  public struct Result {
    public let context: KeyedOverlayState.Context
    public let menuVisible: Bool
  }

  public static func evaluate(frame: CGRect, visibleFrame: CGRect, bandFrame: CGRect,
                              windows: [Window]?) -> Result {
    guard let windows, valid(frame), valid(visibleFrame), valid(bandFrame),
          frame.contains(visibleFrame), frame.contains(bandFrame) else {
      return Result(context: .unknown, menuVisible: false)
    }
    let tolerance: CGFloat = 2
    let menuVisible = windows.contains {
      $0.owner == .windowServer && $0.layer == 24 && valid($0.bounds)
        && abs($0.bounds.minX - bandFrame.minX) <= tolerance
        && abs($0.bounds.maxX - bandFrame.maxX) <= tolerance
        && abs($0.bounds.maxY - bandFrame.maxY) <= tolerance
        && $0.bounds.height <= bandFrame.height + tolerance
    }
    // On notched Macs full screen can reserve the camera housing. Test the full content
    // height below the band too. Partial-width windows cover Split View; revealed menus
    // do not change this test. Ignore our own band/corners and desktop/Dock windows.
    let coveringApp = windows.contains {
      $0.owner == .application && $0.layer >= 0 && valid($0.bounds)
        && $0.bounds.intersection(frame).width >= frame.width * 0.4
        && $0.bounds.minY <= frame.minY + tolerance
        && $0.bounds.maxY >= bandFrame.minY - tolerance
    }
    let noReservedTop = visibleFrame.maxY >= frame.maxY - tolerance
    return Result(context: coveringApp || noReservedTop ? .fullScreen : .desktop,
                  menuVisible: menuVisible)
  }

  private static func valid(_ rect: CGRect) -> Bool {
    !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0
      && [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite)
  }
}
