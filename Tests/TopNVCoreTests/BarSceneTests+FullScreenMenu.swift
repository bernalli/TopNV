import CoreGraphics
import XCTest

@testable import TopNVCore

/// A full-screen Space that shows the menu bar: the backdrop, a reserved top and the menu surface,
/// measured on 19 and 20 November. The band must enter there as it does on a desktop.
extension BarSceneTests {
  private var backdrop: Window { background(MenuBarEvidence.fullScreenBackdropLayer) }
  private var covering: Window { Window(owner: .application, layer: 0, bounds: display().frame) }

  private func plan(
    _ scene: BarScene, _ screen: BarDisplay? = nil,
    entrance: [UInt32: BarEntrance]? = nil
  ) throws -> BarDisplayPlan {
    let screen = screen ?? display()
    let plan = BarSurface.plan(
      geometry: [1: screen], scene: scene, entrance: entrance ?? scene.entrances,
      settings: settings)
    return try XCTUnwrap(plan.displays[1])
  }

  private func returnStarts(_ effects: BarSampleEffects) -> Bool {
    effects.entranceEffects.contains { effect in
      if case .start = effect { return true }
      return false
    }
  }

  /// The row a full-screen scene shows outside an entrance: band and corners whole, key gated.
  private func checkFullScreenRow(_ display: BarDisplayPlan, label: String) {
    XCTAssertEqual(display.kind, .fullScreen, label)
    XCTAssertEqual(display.band.mask, BarMask.none, label)
    XCTAssertEqual(display.band.alpha, .value(1), label)
    XCTAssertEqual(display.key.mask, BarMask.none, label)
    XCTAssertEqual(display.edge.alpha, .value(0), label)
    for corner in display.corners.values { XCTAssertEqual(corner.alpha, .value(1), label) }
  }

  func testAFullScreenSpaceThatShowsTheMenuBarEntersAfterEitherReveal() throws {
    for layer in [18, 19] {
      let label = "layer \(layer)"
      var scene = scene()
      _ = scene.handle(sample([menu(), backdrop], now: 1))
      checkFullScreenRow(try plan(scene), label: label)

      _ = scene.handle(sample([menu(), backdrop, background(layer)], now: 2))
      XCTAssertEqual(scene.kinds[1], layer == 19 ? .overview : .revealed, label)
      let back = layer == 19 ? [menu(), backdrop, background(19, alpha: 0.8)] : [menu(), backdrop]
      let effects = scene.handle(sample(back, now: 3))
      XCTAssertEqual(effects.entranceEffects.first, .start(display: 1, returnSignal: 103), label)
      XCTAssertEqual(scene.kinds[1], .fullScreen, label)

      scene.advanceEntrance(display: 1, elapsedMS: 100)
      let entering = try plan(scene)
      XCTAssertEqual(entering.kind, .fullScreen, label)
      XCTAssertNotEqual(entering.band.mask, BarMask.none, label)
      XCTAssertEqual(entering.key.mask, entering.band.mask, label)
      XCTAssertNotNil(entering.key.backdropExtent, label)
      XCTAssertEqual(entering.edge.alpha, .value(0), label)
      XCTAssertEqual(entering.edge.mask, BarMask.none, label)
      for corner in entering.corners.values {
        XCTAssertEqual(corner.alpha, .value(BarEntranceMask.cornerAlpha(elapsedMS: 100)), label)
      }

      scene.finishEntrance(display: 1)
      checkFullScreenRow(try plan(scene), label: label)
    }
  }

  /// Every other full-screen case keeps today's behavior: no entrance, the row stays whole.
  func testWithoutAShownMenuBarAFullScreenSpaceDoesNotEnter() throws {
    struct Case {
      let name: String
      let screen: BarDisplay?
      let rest: [Window]
      let back: [Window]?
    }
    let slide = background(-1, offset: 240)
    let cases: [Case] = [
      .init(
        name: "top not reserved", screen: display(hiddenMenu: true), rest: [menu(), backdrop],
        back: [menu(), backdrop]),
      .init(name: "menu hidden", screen: nil, rest: [backdrop], back: [backdrop]),
      .init(
        name: "sliding", screen: nil, rest: [menu(), backdrop], back: [menu(), backdrop, slide]),
      .init(name: "list unavailable", screen: nil, rest: [menu(), backdrop], back: nil),
      .init(
        name: "covering app", screen: nil, rest: [menu(), backdrop, covering],
        back: [menu(), backdrop, covering])
    ]
    for item in cases {
      for layer in [18, 19] {
        let label = "\(item.name) layer \(layer)"
        let screens = item.screen.map { [$0] }
        var scene = scene(screens)
        _ = scene.handle(sample(item.rest, screens, now: 1))
        _ = scene.handle(sample(item.rest + [background(layer)], screens, now: 2))
        // The return: the overview fades, then the surface leaves. Both samples carry the case.
        let fading = item.back.map { $0 + [background(layer, alpha: 0.8)] }
        var started = returnStarts(scene.handle(sample(fading, screens, now: 3)))
        started = returnStarts(scene.handle(sample(item.back, screens, now: 4))) || started
        XCTAssertFalse(started, label)
        XCTAssertTrue(scene.entrances.isEmpty, label)
        let row = try plan(scene, item.screen)
        XCTAssertEqual(row.band.mask, BarMask.none, label)
        XCTAssertEqual(row.key.mask, BarMask.none, label)
        if item.back != nil && item.name != "sliding" { checkFullScreenRow(row, label: label) }
      }
    }
  }

  /// The table follows the permission of the latest sample, not the scene alone: an entrance that
  /// ends in a sample with a covering app shows the band whole, as before.
  func testAnEntranceInASceneWithoutPermissionShowsTheBandWhole() throws {
    let running = [UInt32(1): BarEntrance(origin: .returnSignal, elapsedMS: 100, durationMS: 570)]
    var scene = scene()
    _ = scene.handle(sample([menu()], now: 1))
    _ = scene.handle(sample([menu(), background(19)], now: 2))
    XCTAssertEqual(
      scene.handle(sample([menu(), background(19, alpha: 0.8)], now: 3)).entranceEffects,
      [.start(display: 1, returnSignal: 103)])
    let effects = scene.handle(sample([menu(), covering], now: 4))
    XCTAssertEqual(effects.entranceEffects, [.restore(display: 1)])
    XCTAssertEqual(scene.kinds[1], .fullScreen)
    checkFullScreenRow(try plan(scene, entrance: running), label: "covering app")

    _ = scene.handle(sample([menu(), backdrop], now: 5))
    XCTAssertNotEqual(try plan(scene, entrance: running).band.mask, BarMask.none)
  }
}
