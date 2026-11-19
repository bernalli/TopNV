import XCTest
@testable import TopNVCore

/// The window lists sampled at rest on 18 and 19 November: the full-screen Space of a browser
/// and the desktop next to it. The signal is only traced for now.
final class FullScreenBackdropTests: XCTestCase {
  private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let band = CGRect(x: 0, y: 949, width: 1512, height: 33)
  private let visible = CGRect(x: 60, y: 0, width: 1452, height: 949)

  private func row(_ owner: String, pid: Int32, layer: Int, left: Int = 0, top: Int = 0,
                   width: Int = 1512, height: Int = 982, alpha: Double = 1) -> [String: Any] {
    [kCGWindowOwnerName as String: owner, kCGWindowOwnerPID as String: pid,
     kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha,
     kCGWindowBounds as String: ["X": left, "Y": top, "Width": width, "Height": height]]
  }

  private func backdrop(_ rows: [[String: Any]], frame: CGRect? = nil) -> Bool {
    let bar = row("Window Server", pid: 652, layer: 24, height: 33)
    let windows = MenuBarEvidence.windows(from: rows + [bar], ownPID: 42, primaryScreenHeight: 982)
    return MenuBarEvidence.evaluate(frame: frame ?? screen, visibleFrame: visible, bandFrame: band,
                                    windows: windows).fullScreenBackdrop
  }

  private var desktopSpace: [[String: Any]] {
    [row("Dock", pid: 1298, layer: 20), row("Screenshot", pid: 700, layer: 24),
     row("Terminal", pid: 1294, layer: 0, left: 60, top: 33, width: 1452, height: 949),
     row("WindowManager", pid: 1005, layer: -2_147_483_624)]
  }

  private var fullScreenSpace: [[String: Any]] {
    [row("Screenshot", pid: 700, layer: 24), row("WindowManager", pid: 1005, layer: -2_147_483_622),
     row("WindowManager", pid: 1005, layer: -2_147_483_624)]
  }

  func testTheMeasuredSpacesAreToldApart() {
    XCTAssertEqual(MenuBarEvidence.fullScreenBackdropLayer, -2_147_483_622)
    XCTAssertFalse(backdrop(desktopSpace))
    XCTAssertTrue(backdrop(fullScreenSpace))
    XCTAssertTrue(backdrop(Array(fullScreenSpace.reversed()) + desktopSpace))
  }

  func testOnlyAVisibleWindowManagerWindowInPlaceOnThisDisplayCounts() {
    let layer = -2_147_483_622
    let manager = "WindowManager"
    for other in [
      row(manager, pid: 1005, layer: layer, left: 43), row(manager, pid: 1005, layer: layer, top: 3),
      row(manager, pid: 1005, layer: layer, left: 1512), row(manager, pid: 1005, layer: layer, alpha: 0),
      row(manager, pid: 1005, layer: layer, width: 1500), row(manager, pid: 1005, layer: layer + 1),
      row(manager, pid: 1005, layer: 18), row("Dock", pid: 1298, layer: layer),
      row("Browser", pid: 500, layer: layer), row(manager, pid: 42, layer: layer)
    ] {
      XCTAssertFalse(backdrop(desktopSpace + [other]), "\(other)")
    }
    XCTAssertFalse(backdrop(fullScreenSpace, frame: .null))
    XCTAssertFalse(MenuBarEvidence.evaluate(frame: screen, visibleFrame: visible, bandFrame: band,
                                            windows: nil).fullScreenBackdrop)
  }
}
