import XCTest
@testable import TopNVCore

final class SlidingDesktopTests: XCTestCase {
  private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let band = CGRect(x: 0, y: 949, width: 1512, height: 33)

  // Quartz samples from 08:59:07–10, converted to global AppKit coordinates.
  // The original sampler omitted short Window Server surfaces. Use the menu result
  // reported by the concurrent gate trace for those surfaces.
  private func sample(_ origins: [CGFloat], menu: Bool, fullScreen: Bool = false) -> MenuBarEvidence.Result {
    var windows: [MenuBarEvidence.Window] = [
      .init(owner: .desktop, layer: 20, bounds: frame), // Dock
      .init(owner: .desktop, layer: 24, bounds: frame), // Screenshot
      .init(owner: .application, layer: 0, bounds: CGRect(x: 60 + origins[0], y: 0, width: 1452, height: 949))
    ]
    for origin in origins {
      windows.append(.init(owner: .desktop, layer: -2_147_483_624, bounds: frame.offsetBy(dx: origin, dy: 0),
                           isWindowManager: true))
      windows.append(.init(owner: .ownApp, layer: 26, bounds: band.offsetBy(dx: origin, dy: 0)))
    }
    if menu { windows.append(.init(owner: .windowServer, layer: 24, bounds: band)) }
    if fullScreen { windows.append(.init(owner: .application, layer: 0, bounds: frame)) }
    return MenuBarEvidence.evaluate(frame: frame, visibleFrame: CGRect(x: 60, y: 0, width: 1452, height: 949),
                                    bandFrame: band, windows: windows)
  }

  private func input(_ origins: [CGFloat], menu: Bool, id: Int?, appearance: KeyedOverlayState.Appearance,
                     time: Double, fullScreen: Bool = false) -> KeyedOverlayState.Input {
    let evidence = sample(origins, menu: menu, fullScreen: fullScreen)
    return .init(activeWindowIDs: id.map { [$0] } ?? [], appearance: appearance, context: evidence.context,
                 menuVisible: evidence.menuVisible, enabled: true, now: time)
  }

  func testSwipeKeepsEachDesktopsGateBeforeAndAfterNotification() {
    var state = KeyedOverlayState()
    _ = state.update(input([0], menu: true, id: 2, appearance: .dark, time: 1))
    _ = state.update(input([0], menu: true, id: 1, appearance: .light, time: 4.848))
    let samples: [(Double, [CGFloat])] = [(7.647, [-579, 997]), (8.298, [-1571, 5])]
    for (time, origins) in samples {
      _ = state.update(input(origins, menu: false, id: 1,
                             appearance: .light, time: time))
      XCTAssertEqual(state.visibility, [1: true, 2: false])
    }
    // The bar reappears before the old appearance probe has caught up.
    _ = state.update(input([-1575, 1], menu: true, id: 2, appearance: .light, time: 8.465))
    XCTAssertEqual(state.visibility, [1: true, 2: false])
    state.spaceDidChange(now: 8.53)
    _ = state.update(input([0], menu: true, id: 2, appearance: .dark, time: 9.1))

    _ = state.update(input([-1533, 43], menu: false, id: 2, appearance: .dark, time: 9.323))
    _ = state.update(input([-2, 1574], menu: true, id: 1, appearance: .dark, time: 10.231))
    state.spaceDidChange(now: 10.35)
    _ = state.update(input([0], menu: true, id: 1, appearance: .light, time: 10.4))
    XCTAssertEqual(state.visibility, [1: true, 2: false])
  }

  func testMovingDesktopsCannotCreateAnOverlayOrRevealAHiddenOne() {
    var state = KeyedOverlayState()
    XCTAssertNil(state.update(input([-579, 997], menu: true, id: nil, appearance: .light, time: 1)).create)
    _ = state.update(input([0], menu: true, id: 1, appearance: .dark, time: 2))
    _ = state.update(input([-579, 997], menu: true, id: 1, appearance: .light, time: 3))
    XCTAssertEqual(state.visibility[1], false)
  }

  func testStationaryHiddenMenuAndFullScreenStillHideTheOverlay() {
    for origins: [CGFloat] in [[0], [-1512, 0, 1512], [-3500, -1900], [1900, 3500]] {
      var state = KeyedOverlayState()
      _ = state.update(input([0], menu: true, id: 1, appearance: .light, time: 1))
      for time in [2.0, 2.5, 3.0, 4.0] {
        _ = state.update(input(origins, menu: false, id: 1, appearance: .light, time: time))
        XCTAssertEqual(state.visibility[1], false)
      }
    }
    var state = KeyedOverlayState()
    _ = state.update(input([0], menu: true, id: 1, appearance: .light, time: 1))
    _ = state.update(input([-579, 997], menu: false, id: 1, appearance: .light, time: 2, fullScreen: true))
    XCTAssertEqual(state.visibility[1], false)
  }
}
