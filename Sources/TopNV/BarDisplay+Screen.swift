import AppKit
import TopNVCore

extension NSScreen {
  var displayID: CGDirectDisplayID? {
    deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
  }
}

extension BarDisplay {
  @MainActor init?(screen: NSScreen) {
    guard let id = screen.displayID else { return nil }
    let width: CGFloat
    if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
      width = max(0, right.minX - left.maxX)
    } else {
      width = 0
    }
    self.init(id: id, frame: screen.frame, visibleFrame: screen.visibleFrame,
              safeAreaTop: screen.safeAreaInsets.top, scale: screen.backingScaleFactor,
              notchWidth: width, isBuiltin: CGDisplayIsBuiltin(id) != 0)
  }
}
