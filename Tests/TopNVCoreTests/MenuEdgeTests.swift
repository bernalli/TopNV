import CoreGraphics
import XCTest
@testable import TopNVCore

final class MenuEdgeTests: XCTestCase {
  private let screen = CGRect(x: -1512, y: 100, width: 1512, height: 982)
  private var menu: CGRect { CGRect(x: -1512, y: 1049, width: 1512, height: 33) }

  private func edge(menuBounds: CGRect?, autoHide: Bool = false,
                    extra: [MenuBarEvidence.Window] = []) -> CGRect? {
    var windows = [MenuBarEvidence.Window(owner: .desktop, layer: -100, bounds: screen, isWindowManager: true)]
    if let menuBounds { windows.append(.init(owner: .windowServer, layer: 24, bounds: menuBounds)) }
    windows += extra
    let visible = autoHide ? screen : CGRect(x: -1512, y: 100, width: 1512, height: 949)
    // Leave room below both candidate menu surfaces to observe which one was selected.
    let band = CGRect(x: screen.minX, y: screen.maxY - 39, width: screen.width, height: 39)
    let result = MenuBarEvidence.evaluate(frame: screen, visibleFrame: visible, bandFrame: band, windows: windows)
    guard BarSceneKind.classify(result, screenPresent: true) == .desktop else { return nil }
    return BarGeometry.edge(menuBounds: result.menuBounds, band: band)
  }

  func testCoverStartsBelowTheVisibleMenuAndEndsAtTheFirstUnaffectedRow() throws {
    for autoHide in [false, true] {
      let cover = try XCTUnwrap(edge(menuBounds: menu, autoHide: autoHide))
      XCTAssertEqual(cover.minX, screen.minX)
      XCTAssertEqual(cover.width, screen.width)
      for scale in [CGFloat(1), 2, 3] {
        XCTAssertEqual((screen.maxY - cover.maxY) * scale, 33 * scale)
        XCTAssertEqual((screen.maxY - cover.minY) * scale, 35 * scale)
      }
    }
  }

  func testCoverTracksTheActualMenuAndDisappearsWithIt() {
    let shorter = CGRect(x: menu.minX, y: menu.minY + 4, width: menu.width, height: 29)
    XCTAssertEqual(edge(menuBounds: shorter, autoHide: true),
                   CGRect(x: shorter.minX, y: shorter.minY - 2, width: shorter.width, height: 2))
    XCTAssertNil(edge(menuBounds: nil, autoHide: true))
    XCTAssertNil(edge(menuBounds: menu, extra: [.init(owner: .application, layer: 0, bounds: screen)]))
    XCTAssertNil(edge(menuBounds: menu, extra: [.init(owner: .desktop, layer: 19, bounds: screen,
                                                      isWindowManager: true)]))
  }

  func testCoverFindsAVisibleStationaryMenuAmongOtherSurfacesAtTheSameLevel() {
    let hidden = MenuBarEvidence.Window(owner: .windowServer, layer: 24, bounds: menu, alpha: 0)
    let moving = MenuBarEvidence.Window(owner: .windowServer, layer: 24, bounds: menu.offsetBy(dx: 1, dy: 0))
    let visible = MenuBarEvidence.Window(owner: .windowServer, layer: 24, bounds: menu)
    let expected = CGRect(x: -1512, y: 1047, width: 1512, height: 2)
    XCTAssertEqual(edge(menuBounds: nil, autoHide: true, extra: [hidden, moving, visible]), expected)
  }

  func testCoverUsesTheLowerEdgeOfMatchingMenuSurfacesInEitherOrder() {
    let shorter = CGRect(x: menu.minX, y: menu.minY + 4, width: menu.width, height: 29)
    let surfaces = [shorter, menu].map { MenuBarEvidence.Window(owner: .windowServer, layer: 24, bounds: $0) }
    let expected = CGRect(x: -1512, y: 1047, width: 1512, height: 2)
    for autoHide in [false, true] {
      XCTAssertEqual(edge(menuBounds: nil, autoHide: autoHide, extra: surfaces), expected)
      XCTAssertEqual(edge(menuBounds: nil, autoHide: autoHide, extra: Array(surfaces.reversed())), expected)
    }
  }

  func testCoverUsesAnAlternateLayerOnlyWithoutAVisiblePreferredSurface() {
    let taller = CGRect(x: menu.minX, y: menu.minY - 4, width: menu.width, height: 37)
    let alternate = MenuBarEvidence.Window(owner: .windowServer, layer: 25, bounds: taller)
    let hiddenPreferred = MenuBarEvidence.Window(owner: .windowServer, layer: 24, bounds: menu, alpha: 0)
    XCTAssertEqual(edge(menuBounds: nil, extra: [hiddenPreferred, alternate]),
                   CGRect(x: -1512, y: 1043, width: 1512, height: 2))
    XCTAssertEqual(edge(menuBounds: menu, extra: [alternate]),
                   CGRect(x: -1512, y: 1047, width: 1512, height: 2))
    for layer in [0, 19, MenuBarEvidence.overlayLevel, MenuBarEvidence.overlayLevel + 1] {
      XCTAssertNil(edge(menuBounds: nil, extra: [.init(owner: .windowServer, layer: layer, bounds: menu)]))
    }
  }
}
