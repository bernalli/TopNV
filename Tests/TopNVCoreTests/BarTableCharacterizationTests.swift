import CoreGraphics
import XCTest
@testable import TopNVCore

final class BarTableCharacterizationTests: XCTestCase {
  private typealias Window = MenuBarEvidence.Window
  private let frame = CGRect(x: -1512, y: 100, width: 1512, height: 982)
  private var menu: Window {
    Window(owner: .windowServer, layer: 24, bounds: CGRect(x: -1512, y: 1049, width: 1512, height: 33))
  }
  private var band: CGRect { CGRect(x: -1512, y: 1048, width: 1512, height: 34) }

  private func background(_ layer: Int, offset: CGFloat = 0) -> Window {
    Window(owner: .desktop, layer: layer, bounds: frame.offsetBy(dx: offset, dy: 0), isWindowManager: true)
  }

  // Expected key decisions once the Space has settled, including after a stuck slide.
  private enum KeyRule { case show, hide, maskAll, closeActive, closeActiveAndMaskOthers }

  private struct Fixture {
    let name: String
    let scene: BarSceneKind
    let windows: [Window]?
    let key: KeyRule
    var entrance: BandEntrance.Sample? = .unavailable
    var edge = false
    var autoHidden = false
    var systemFullScreen = false
    var present = true
  }

  private var fixtures: [Fixture] {
    let reveal = background(18), overview = background(19), slide = background(-1, offset: 300)
    let native = Window(owner: .application, layer: 0,
                        bounds: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 949),
                        isFrontmostApp: true)
    let covering = Window(owner: .application, layer: 0, bounds: frame)
    return [
      .init(name: "measured menu", scene: .desktop, windows: [menu], key: .show, entrance: .desktop, edge: true),
      .init(name: "unmeasured visible menu", scene: .desktop,
            windows: [Window(owner: .windowServer, layer: 5, bounds: menu.bounds)], key: .show, entrance: .desktop),
      .init(name: "auto-hidden menu", scene: .desktop, windows: [background(-1)], key: .hide,
            entrance: .desktop, autoHidden: true),
      .init(name: "show desktop", scene: .revealed, windows: [menu, reveal], key: .maskAll, entrance: .revealed),
      .init(name: "overview", scene: .overview, windows: [menu, overview], key: .maskAll, entrance: .revealed),
      .init(name: "reveal listed first", scene: .revealed, windows: [menu, reveal, overview], key: .maskAll,
            entrance: .revealed),
      .init(name: "overview listed first", scene: .overview, windows: [menu, overview, reveal], key: .maskAll,
            entrance: .revealed),
      .init(name: "native full screen", scene: .fullScreen, windows: [menu, native], key: .closeActive,
            systemFullScreen: true),
      .init(name: "covering window", scene: .fullScreen, windows: [menu, covering], key: .hide),
      .init(name: "full-screen backdrop", scene: .fullScreen,
            windows: [menu, background(MenuBarEvidence.fullScreenBackdropLayer)], key: .show),
      .init(name: "sliding with menu", scene: .sliding, windows: [menu, slide], key: .show),
      .init(name: "sliding without menu", scene: .sliding, windows: [slide], key: .hide),
      .init(name: "reveal during slide", scene: .revealed, windows: [menu, reveal, slide], key: .maskAll),
      .init(name: "reveal over native full screen", scene: .revealed, windows: [menu, reveal, native],
            key: .closeActiveAndMaskOthers, systemFullScreen: true),
      .init(name: "overview over native full screen", scene: .overview, windows: [menu, overview, native],
            key: .closeActiveAndMaskOthers, systemFullScreen: true),
      .init(name: "unavailable list", scene: .unknown, windows: nil, key: .hide),
      .init(name: "missing display", scene: .absent, windows: nil, key: .hide, entrance: nil, present: false)
    ]
  }

  private func evidence(_ fixture: Fixture, bandHeight: CGFloat? = nil) -> MenuBarEvidence.Result? {
    guard fixture.present else { return nil }
    let visible = fixture.autoHidden ? frame : CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 949)
    let height = bandHeight ?? band.height
    let strip = CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height)
    let raw = MenuBarEvidence.evaluate(frame: frame, visibleFrame: visible, bandFrame: strip,
                                       windows: fixture.windows, systemFullScreen: fixture.systemFullScreen)
    var desktopReturn = DesktopReturn()
    return desktopReturn.resolve(raw, on: frame, windows: fixture.windows)
  }

  func testBandAlphaFollowsOnlyTheReveal() {
    // KeyedOverlayController.swift:260-273 keeps the previous visibility for an absent display.
    // OverlayController.swift:240-244 applies the resulting reveal set to each band's alpha.
    for fixture in fixtures {
      let sample = evidence(fixture)
      XCTAssertEqual(BarSceneKind.classify(sample, screenPresent: fixture.present), fixture.scene, fixture.name)
      let visible = sample.map { CornerVisibility.visible($0) }
      let expected: Bool? = fixture.scene == .absent ? nil : fixture.scene != .revealed && fixture.scene != .overview
      XCTAssertEqual(visible, expected, fixture.name)
    }
  }

  func testCornersFollowTheEvidenceWithHideNotchOff() {
    // KeyedOverlayController.swift:266-273 evaluates a one-point strip when Hide Notch is off.
    // CornerVisibility.swift:8-10 also keeps corners visible when the list is unavailable.
    for fixture in fixtures where fixture.present {
      let expected = fixture.scene != .revealed && fixture.scene != .overview
      XCTAssertEqual(CornerVisibility.visible(evidence(fixture, bandHeight: 1)), expected, fixture.name)
    }
  }

  func testEdgeNeedsAPermittedDesktopAndAMeasuredMenu() {
    // MenuBarEvidence.swift:42-45 anchors the cover to the measured menu, independently of the band.
    // KeyedOverlayController.swift:260-264 withdraws it when the display is absent.
    let edge = CGRect(x: menu.bounds.minX, y: menu.bounds.minY - 2, width: menu.bounds.width, height: 2)
    for fixture in fixtures {
      XCTAssertEqual(evidence(fixture)?.menuEdgeFrame, fixture.edge ? edge : nil, fixture.name)
    }
  }

  private func input(_ evidence: MenuBarEvidence.Result, active: [Int], now: Double) -> KeyedOverlayState.Input {
    .init(activeWindowIDs: active, appearance: .light, context: evidence.context, menuVisible: evidence.menuVisible,
          enabled: true, now: now, desktopRevealed: evidence.desktopRevealed, spaceSliding: evidence.spaceSliding,
          nativeFullScreen: evidence.nativeFullScreen)
  }

  // Keys 1 and 3 were visible on their respective Spaces; key 2 was hidden.
  private func populatedState() -> KeyedOverlayState {
    var state = KeyedOverlayState()
    for id in [1, 2, 3] {
      _ = state.update(.init(activeWindowIDs: [id], appearance: .light, context: .desktop,
                             menuVisible: id != 2, enabled: true, now: 0))
    }
    return state
  }

  func testKeyGatesPerScene() throws {
    // KeyedOverlayState.swift:88-110 bounds slide settling; :121-160 closes, gates and reserves independently.
    // KeyedOverlayController.swift:89-92 skips absent displays; :141-150 applies only the returned commands.
    let slide = try XCTUnwrap(evidence(.init(name: "slide onset", scene: .sliding,
                                             windows: [background(-1, offset: 300)], key: .hide)))
    for fixture in fixtures {
      for settling in [false, true] {
        for active in [[2, 1, 2], [Int]()] {
          var state = populatedState()
          if settling {
            state.spaceDidChange(now: 7.9)
          } else {
            // At 8 s even a continuing slide has passed the 5 s cap and the 0.5 s settle time.
            _ = state.update(input(slide, active: [1], now: 2))
            _ = state.update(input(slide, active: [1], now: 7))
          }
          let decision = evidence(fixture).map { state.update(input($0, active: active, now: 8)) }
          let label = "\(fixture.name), settling=\(settling), active=\(active)"
          let initial = [1: true, 2: false, 3: true]
          guard fixture.present else {
            XCTAssertNil(decision, label)
            XCTAssertEqual(state.visibility, initial, label)
            continue
          }
          let result = try XCTUnwrap(decision, label)
          let mask = fixture.key == .maskAll || fixture.key == .closeActiveAndMaskOthers
          let closeAll = !settling && (fixture.key == .closeActive || fixture.key == .closeActiveAndMaskOthers)
          let close = active.isEmpty ? [] : (closeAll ? [1, 2] : [2])
          var gates: [Int: Bool] = [:]
          if mask {
            gates[3] = false
            if !close.contains(1) { gates[1] = false }
          } else if !settling && !active.isEmpty && !closeAll {
            gates[1] = fixture.key == .show
          }
          XCTAssertEqual(result.close, close, label)
          XCTAssertEqual(result.gates, gates, label)
          XCTAssertEqual(result.create != nil, !settling && active.isEmpty && fixture.key == .show, label)
          var retained = initial
          for id in close { retained[id] = nil }
          retained.merge(gates) { _, shown in shown }
          XCTAssertEqual(state.visibility, retained, label)
        }
      }
    }
  }

  func testAKeyVisibleBeforeARevealResumesBeforeSettling() throws {
    // KeyedOverlayState.swift:166-189 restores remembered active and inactive keys before the settle deadline.
    let desktop = try XCTUnwrap(evidence(.init(name: "desktop", scene: .desktop, windows: [menu], key: .show)))
    let reveal = try XCTUnwrap(evidence(.init(name: "reveal", scene: .revealed,
                                              windows: [menu, background(18)], key: .maskAll)))
    for keeper in [1, 2] {
      var state = populatedState()
      state.spaceDidChange(now: 1)
      let masked = state.update(input(reveal, active: [keeper], now: 1.1))
      XCTAssertEqual(masked.gates, keeper == 1 ? [1: false, 3: false] : [1: false, 2: false, 3: false])
      let resumed = state.update(input(desktop, active: [keeper], now: 1.2))
      XCTAssertEqual(resumed.gates, [1: true, 3: true])
      XCTAssertEqual(state.visibility, [1: true, 2: false, 3: true])
    }
  }

  func testPlateFollowsTheKeyedBottomMaskRule() throws {
    // KeyedOverlayController.swift:170-176,201-210 attaches the plate to the keyed window's root at creation.
    // ScreenGeometry.swift:46-51 rounds its top edge down the display to the next whole pixel.
    let size = band.size
    let firstPixels: [(menuHeight: CGFloat, pixelsByScale: [CGFloat])] = [
      (33, [26, 51, 77]), (0, [27, 53, 80])
    ]
    var state = KeyedOverlayState()
    let desktop = try XCTUnwrap(evidence(.init(name: "desktop", scene: .desktop, windows: [menu], key: .show)))
    let reservation = try XCTUnwrap(state.update(input(desktop, active: [], now: 0)).create)
    XCTAssertTrue(state.visibility.isEmpty)
    XCTAssertTrue(state.commit(reservation, windowID: 1))
    XCTAssertEqual(state.visibility, [1: false])
    for (menuHeight, pixels) in firstPixels {
      for (scale, firstPixel) in zip([CGFloat(1), 2, 3], pixels) {
        for flipped in [false, true] {
          let plate = ScreenGeometry.keyedBottomMask(size: size, menuHeight: menuHeight, scale: scale, flipped: flipped)
          let top = firstPixel / scale
          XCTAssertEqual(plate, CGRect(x: 0, y: flipped ? top : 0, width: size.width, height: size.height - top))
        }
      }
    }
    state.forget(1)
    XCTAssertTrue(state.visibility.isEmpty)
  }

  func testEntranceStartsOnlyOnADesktopScene() {
    // BandEntrance.swift:18-28,37-39 uses the evidence for activation and reveal returns; absence restores once.
    let id: UInt32 = 1
    for fixture in fixtures {
      let sample = evidence(fixture).map { BandEntrance.Sample($0) }
      XCTAssertEqual(sample, fixture.entrance, fixture.name)
      let samples = sample.map { [id: $0] } ?? [:]
      var entrance = BandEntrance()
      let activation = entrance.update(.settings, enabled: true, samples: samples, reduceMotion: false)
      let expected: BandEntrance.Action? = sample.map { _ in fixture.scene == .desktop ? .start : .restore }
      XCTAssertEqual(activation[id], expected, fixture.name)

      _ = entrance.update(.sample, enabled: true, samples: [id: .desktop], reduceMotion: false)
      _ = entrance.update(.sample, enabled: true, samples: [id: .revealed], reduceMotion: false)
      let afterReveal = entrance.update(.sample, enabled: true, samples: samples, reduceMotion: false)
      XCTAssertEqual(afterReveal[id], fixture.scene == .desktop ? .start : .restore, fixture.name)
      let disabled = entrance.update(.sample, enabled: false, samples: samples, reduceMotion: false)
      XCTAssertEqual(disabled[id], fixture.present ? .restore : nil, fixture.name)
    }
  }
}
