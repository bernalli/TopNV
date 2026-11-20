import CoreGraphics
import XCTest
import TopNVCore

final class BarSceneKindTests: XCTestCase {
  private typealias Window = MenuBarEvidence.Window
  private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let band = CGRect(x: 0, y: 948, width: 1512, height: 34)

  private var menu: Window { Window(owner: .windowServer, layer: 24, bounds: band) }
  private var app: Window { Window(owner: .application, layer: 0, bounds: frame, isFrontmostApp: true) }
  private func desktop(_ layer: Int, offset: CGFloat = 0) -> Window {
    Window(owner: .desktop, layer: layer, bounds: frame.offsetBy(dx: offset, dy: 0), isWindowManager: true)
  }

  private func evaluate(_ windows: [Window]?, autoHidden: Bool = false,
                        fullScreen: Bool = false) -> MenuBarEvidence.Result {
    let visible = autoHidden ? frame : CGRect(x: 0, y: 0, width: frame.width, height: band.minY)
    return MenuBarEvidence.evaluate(frame: frame, visibleFrame: visible, bandFrame: band,
                                   windows: windows, systemFullScreen: fullScreen)
  }

  func testEachEvidenceFixtureMapsToOneScene() {
    let fixtures: [([Window]?, BarSceneKind)] = [
      (nil, .unknown), ([menu], .desktop), ([desktop(18)], .revealed), ([desktop(19)], .overview),
      ([desktop(-1, offset: 300)], .sliding), ([app], .fullScreen)
    ]
    for (windows, scene) in fixtures {
      XCTAssertEqual(BarSceneKind.classify(evaluate(windows), screenPresent: true), scene)
      XCTAssertEqual(BarSceneKind.classify(evaluate(windows), screenPresent: false), .absent)
    }
    XCTAssertEqual(BarSceneKind.classify(nil, screenPresent: true), .unknown)
    XCTAssertEqual(BarSceneKind.classify(nil, screenPresent: false), .absent)
  }

  func testRevealWinsOverSlidingAndFullScreen() {
    for (layer, scene) in [(18, BarSceneKind.revealed), (19, .overview)] {
      let evidence = evaluate([app, desktop(-1, offset: 200), desktop(layer)], fullScreen: true)
      XCTAssertTrue(evidence.nativeFullScreen)
      XCTAssertTrue(evidence.spaceSliding)
      XCTAssertEqual(BarSceneKind.classify(evidence, screenPresent: true), scene)
    }
  }

  func testSceneAgreesWithTheCornerAndEntranceRules() {
    var random = BarTestGenerator()
    let candidates = [menu, app, desktop(-1), desktop(18), desktop(19), desktop(-1, offset: 300),
                      desktop(MenuBarEvidence.fullScreenBackdropLayer)]
    for _ in 0..<1000 {
      let windows = (0..<random.next(8)).map { _ in candidates[random.next(candidates.count)] }
      let evidence = evaluate(windows, autoHidden: random.next(2) == 0, fullScreen: random.next(2) == 0)
      let scene = BarSceneKind.classify(evidence, screenPresent: true)
      XCTAssertEqual(scene == .revealed || scene == .overview, !CornerVisibility.visible(evidence))
      XCTAssertEqual(scene == .desktop, BandEntrance.Sample(evidence) == .desktop)
    }
  }
}

struct BarTestGenerator {
  private var seed: UInt64 = 0x9E37_79B9_7F4A_7C15

  mutating func next(_ bound: Int) -> Int {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Int((seed >> 33) % UInt64(bound))
  }
}
