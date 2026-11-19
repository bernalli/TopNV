import XCTest
@testable import TopNVCore

/// The rounded corners of a display step aside while its desktop is revealed, as in Mission
/// Control. Missing or unknown evidence never hides them.
final class CornerVisibilityTests: XCTestCase {
  private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let visible = CGRect(x: 0, y: 60, width: 1512, height: 888)
  private let band = CGRect(x: 0, y: 948, width: 1512, height: 34)
  private let external = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
  private let externalVisible = CGRect(x: 1512, y: 0, width: 1920, height: 1055)

  private var menu: MenuBarEvidence.Window {
    .init(owner: .windowServer, layer: 24, bounds: band)
  }

  private func windowManager(_ bounds: CGRect, layer: Int = 18, alpha: Double = 1) -> MenuBarEvidence.Window {
    .init(owner: .desktop, layer: layer, bounds: bounds, isWindowManager: true, alpha: alpha)
  }

  private func corners(_ windows: [MenuBarEvidence.Window]?, bandFrame: CGRect?) -> Bool {
    CornerVisibility.visible(frame: frame, visibleFrame: visible, bandFrame: bandFrame, windows: windows)
  }

  func testTheCornersStepAsideWhileTheDesktopIsRevealed() {
    let revealed = [menu, windowManager(frame)]
    XCTAssertFalse(corners(revealed, bandFrame: band))
    // Hide Notch off or no notch: no band, the evidence is read all the same.
    XCTAssertFalse(corners(revealed, bandFrame: nil))
    // A menu bar that hides itself reserves no strip at the top.
    XCTAssertFalse(CornerVisibility.visible(
      frame: frame, visibleFrame: CGRect(x: 0, y: 60, width: 1512, height: 922), bandFrame: nil,
      windows: revealed))
    // Only the display whose desktop is revealed.
    let onExternal = [menu, windowManager(external)]
    XCTAssertFalse(CornerVisibility.visible(
      frame: external, visibleFrame: externalVisible, bandFrame: nil, windows: onExternal))
    XCTAssertTrue(corners(onExternal, bandFrame: band))
    XCTAssertTrue(corners(onExternal, bandFrame: nil))
  }

  func testEveryOtherScreenKeepsTheCorners() {
    for windows in [
      [menu],
      [menu, .init(owner: .application, layer: 0, bounds: frame)],
      [menu, .init(owner: .desktop, layer: 24, bounds: frame)],
      [menu, windowManager(CGRect(x: 1400, y: 900, width: 77, height: 70), layer: 16)],
      [menu, windowManager(frame, layer: -2_147_483_624), windowManager(frame, layer: -2_147_483_622)],
      [menu, windowManager(frame, alpha: 0)],
      [menu, windowManager(CGRect(x: 0, y: 0, width: 1300, height: 982))]
    ] {
      XCTAssertTrue(corners(windows, bandFrame: band), "\(windows.map(\.bounds))")
      XCTAssertTrue(corners(windows, bandFrame: nil), "\(windows.map(\.bounds))")
    }
  }

  func testMissingOrUnknownEvidenceNeverHidesTheCorners() {
    XCTAssertTrue(CornerVisibility.visible(nil))
    XCTAssertTrue(corners(nil, bandFrame: band))
    XCTAssertTrue(corners(nil, bandFrame: nil))
    let revealed = [menu, windowManager(frame)]
    let unknown = MenuBarEvidence.evaluate(frame: .null, visibleFrame: visible, bandFrame: band,
                                           windows: revealed)
    XCTAssertEqual(unknown.context, .unknown)
    XCTAssertTrue(CornerVisibility.visible(unknown))
    for invalid in [CGRect.null, .zero, .infinite, CGRect(x: CGFloat.nan, y: 0, width: 1512, height: 982)] {
      XCTAssertTrue(CornerVisibility.visible(frame: invalid, visibleFrame: visible, bandFrame: band,
                                             windows: revealed), "\(invalid)")
      XCTAssertTrue(CornerVisibility.visible(frame: invalid, visibleFrame: visible, bandFrame: nil,
                                             windows: revealed), "\(invalid)")
      XCTAssertTrue(corners(revealed, bandFrame: invalid), "\(invalid)")
    }
    // A visible frame or a band outside the screen.
    XCTAssertTrue(CornerVisibility.visible(frame: frame, visibleFrame: visible.offsetBy(dx: 10, dy: 0),
                                           bandFrame: band, windows: revealed))
    XCTAssertTrue(corners(revealed, bandFrame: band.offsetBy(dx: 0, dy: 40)))
  }

  /// Whatever the windows and the geometry: no list or unknown evidence keeps the corners.
  func testNoListOrUnknownEvidenceKeepsTheCornersForAnyInput() {
    var seed: UInt64 = 7
    func next(_ bound: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int((seed >> 33) % UInt64(bound))
    }
    let rects = [frame, visible, band, external, externalVisible, .null, .zero,
                 CGRect(x: 0, y: 0, width: 1512, height: 2000), band.offsetBy(dx: 0, dy: 40)]
    func window() -> MenuBarEvidence.Window {
      let owner = [MenuBarEvidence.Owner.windowServer, .desktop, .ownApp, .application][next(4)]
      return .init(owner: owner, layer: [-2_147_483_624, -1, 0, 16, 18, 24, 27][next(7)],
                   bounds: rects[next(rects.count)], isWindowManager: next(2) == 0,
                   alpha: [0, 0.5, 1][next(3)])
    }
    for _ in 0..<3000 {
      let screen = rects[next(rects.count)]
      let screenVisible = rects[next(rects.count)]
      let bandFrame: CGRect? = next(3) == 0 ? nil : rects[next(rects.count)]
      let windows = (0..<next(5)).map { _ in window() }
      XCTAssertTrue(CornerVisibility.visible(frame: screen, visibleFrame: screenVisible,
                                             bandFrame: bandFrame, windows: nil))
      let result = CornerVisibility.visible(frame: screen, visibleFrame: screenVisible,
                                            bandFrame: bandFrame, windows: windows)
      if let bandFrame {
        let evidence = MenuBarEvidence.evaluate(frame: screen, visibleFrame: screenVisible,
                                                bandFrame: bandFrame, windows: windows)
        if evidence.context == .unknown { XCTAssertTrue(result) }
        XCTAssertEqual(result, CornerVisibility.visible(evidence))
      }
      if !result {
        // Hidden only with a revealing WindowManager window on that display.
        XCTAssertTrue(windows.contains { $0.isWindowManager && $0.layer >= 0 && $0.alpha > 0 })
      }
    }
  }
}
