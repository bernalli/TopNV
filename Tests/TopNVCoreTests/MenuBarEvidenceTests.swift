import XCTest
@testable import TopNVCore

final class MenuBarEvidenceTests: XCTestCase {
  private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let visible = CGRect(x: 0, y: 60, width: 1512, height: 888)
  private let strip = CGRect(x: 0, y: 948, width: 1512, height: 34)

  private var menu: MenuBarEvidence.Window {
    .init(owner: .windowServer, layer: 24, bounds: strip)
  }

  private func classify(_ windows: [MenuBarEvidence.Window]?,
                        visible: CGRect? = nil) -> MenuBarEvidence.Result {
    MenuBarEvidence.evaluate(frame: frame, visibleFrame: visible ?? self.visible,
                             bandFrame: strip, windows: windows)
  }

  func testNoNamesOrWindowTitlesAreNeededForDesktopEvidence() {
    let result = classify([menu])
    XCTAssertEqual(result.context, .desktop)
    XCTAssertTrue(result.menuVisible)
  }

  func testFullScreenRemainsBlockedWithMenuRevealedAndNotchReserved() {
    for top in [CGFloat(948), 982] {
      for width in [CGFloat(1512), 750] {
        let app = MenuBarEvidence.Window(owner: .application, layer: 0,
                                        bounds: CGRect(x: 0, y: 0, width: width, height: top))
        XCTAssertEqual(classify([menu, app]).context, .fullScreen)
      }
    }
    XCTAssertEqual(classify([menu], visible: frame).context, .fullScreen)
  }

  func testFullHeightApplicationAtAnyNonnegativeLayerBlocksRevealedFullScreenMenu() {
    for layer in [0, 24, 25, 26, 1000] {
      let app = MenuBarEvidence.Window(owner: .application, layer: layer,
                                       bounds: CGRect(x: 0, y: 0, width: 750, height: 948))
      XCTAssertEqual(classify([menu, app]).context, .fullScreen, "layer \(layer)")
    }
  }

  func testDockAndOwnWindowsDoNotTurnDesktopIntoFullScreen() {
    for owner in [MenuBarEvidence.Owner.ownApp, .desktop] {
      XCTAssertEqual(classify([menu, .init(owner: owner, layer: 0, bounds: frame)]).context,
                     .desktop)
    }
  }

  func testUnavailableOrMalformedEvidenceFailsClosed() {
    XCTAssertEqual(classify(nil).context, .unknown)
    XCTAssertFalse(classify([]).menuVisible)
    XCTAssertFalse(classify([.init(owner: .application, layer: 24, bounds: strip)]).menuVisible)
    XCTAssertEqual(classify([menu], visible: .zero).context, .unknown)
  }

  func testNormalWindowBelowMenuAndAboveDockIsNotFullScreen() {
    XCTAssertEqual(classify([menu, .init(owner: .application, layer: 0, bounds: visible)]).context,
                   .desktop)
  }
}
