import CoreGraphics
import XCTest

@testable import TopNVCore

extension BarSceneTests {
  func testMeasuredMenuEndsTheBandAtRow66WithoutAnEdge() throws {
    let screen = menuHeightScreen(gap: 34, safeArea: 32)
    var scene = scene([screen])
    _ = scene.handle(sample([menu()], [screen]))
    let plan = try menuHeightPlan(scene, on: screen)
    XCTAssertEqual(plan.band.pixels, PixelRect(x: 0, y: 0, width: 3024, height: 66))
    XCTAssertNil(plan.edge.frame)
    XCTAssertEqual(plan.blackBottom, 66)
  }

  func testBandCoversTheMeasuredMenuAndNotchWhenPresent() throws {
    let depths: [CGFloat?] = [nil, 32, 33, 34, 37]
    for gap: CGFloat in [33, 34, 37, 44] {
      for safeArea: CGFloat in [0, 32, 38] {
        for depth in depths {
          let screen = menuHeightScreen(gap: gap, safeArea: safeArea)
          var scene = scene([screen])
          let windows = depth.map { [menu(depth: $0)] } ?? []
          _ = scene.handle(sample(windows, [screen]))
          let label = "gap \(gap), menu \(String(describing: depth)), safe area \(safeArea)"
          let frame = scene.bandFrames[1]
          if safeArea == 0 {
            XCTAssertNil(frame, label)
          } else {
            let band = try XCTUnwrap(frame, label)
            XCTAssertEqual(band.height, max(safeArea, depth ?? gap), label)
            XCTAssertEqual(band.maxY, screen.frame.maxY, label)
          }
        }
      }
    }
  }

  func testFullScreenMenuResizesTheBandAndMissingSamplesKeepItsLastMeasurement() throws {
    let screen = display(hiddenMenu: true)
    let backdrop = background(MenuBarEvidence.fullScreenBackdropLayer)
    var scene = scene([screen])
    _ = scene.handle(sample([backdrop], [screen]))
    XCTAssertEqual(scene.bandFrames[1]?.height, 32)

    let measured: [Window]? = [backdrop, menu(depth: 37)]
    for windows in [measured, [backdrop], nil, measured] {
      _ = scene.handle(sample(windows, [screen]))
      XCTAssertEqual(try menuHeightPlan(scene, on: screen).band.frame?.height, 37)
    }
    _ = scene.handle(.screenConfigurationChanged, displays: [screen], settings: settings,
                     entrance: .system, screenRebuildPending: false)
    _ = scene.handle(sample([backdrop], [screen]))
    XCTAssertEqual(scene.bandFrames[1]?.height, 37)
    _ = scene.handle(sample([backdrop, menu()], [screen]))
    XCTAssertEqual(scene.bandFrames[1]?.height, 37)
    _ = scene.handle(sample([backdrop, menu()], [screen]))
    XCTAssertEqual(scene.bandFrames[1]?.height, 33)
  }

  func testAlternatingOrInterruptedMenuDepthsDoNotResizeTheBandOrDrawAnEdge() throws {
    let screen = display()
    var scene = scene()
    _ = scene.handle(sample([menu(depth: 37)]))
    for windows: [Window]? in [[menu()], nil, [menu()], [menu(depth: 37)], [menu()], [menu(depth: 37)]] {
      _ = scene.handle(sample(windows))
      let plan = try menuHeightPlan(scene, on: screen)
      XCTAssertEqual(plan.band.frame?.height, 37)
      XCTAssertNil(plan.edge.frame)
    }
    _ = scene.handle(sample([menu()]))
    XCTAssertEqual(scene.bandFrames[1]?.height, 37)
    _ = scene.handle(sample([menu()]))
    XCTAssertEqual(scene.bandFrames[1]?.height, 33)
  }

  func testDesktopEdgeKeepsTheConfirmedMenuDepthUntilItChanges() throws {
    let screen = menuHeightScreen(gap: 38, safeArea: 38)
    var scene = scene([screen])
    for depth: CGFloat in [33, 34, 33, 34, 33, 34] {
      _ = scene.handle(sample([menu(depth: depth)], [screen]))
      let plan = try menuHeightPlan(scene, on: screen)
      XCTAssertEqual(plan.band.frame?.height, 38)
      XCTAssertEqual(plan.edge.pixels, PixelRect(x: 0, y: 66, width: 3024, height: 4))
    }
    _ = scene.handle(sample([menu(depth: 34)], [screen]))
    let confirmedEdge = PixelRect(x: 0, y: 68, width: 3024, height: 4)
    XCTAssertEqual(try menuHeightPlan(scene, on: screen).edge.pixels, confirmedEdge)

    let hiddenMenu = menuHeightScreen(gap: 0, safeArea: 38)
    _ = scene.handle(sample([background(-1)], [hiddenMenu]))
    let pending = try menuHeightPlan(scene, on: hiddenMenu)
    XCTAssertEqual(pending.kind, .desktop)
    XCTAssertEqual(pending.edge.pixels, confirmedEdge)
    _ = scene.handle(sample([background(-1)], [hiddenMenu]))
    XCTAssertNil(try menuHeightPlan(scene, on: hiddenMenu).edge.frame)
  }

  func testBandGrowsToTheNotchFloorWithoutAMenuMeasurement() throws {
    var scene = scene()
    _ = scene.handle(sample([menu()]))
    let screen = menuHeightScreen(gap: 33, safeArea: 38)
    _ = scene.handle(sample(nil, [screen]))
    XCTAssertEqual(try menuHeightPlan(scene, on: screen).band.frame?.height, 38)
    _ = scene.handle(sample([menu()]))
    XCTAssertEqual(scene.bandFrames[1]?.height, 38)
  }

  func testPersistentMeasurementLossRestoresTheFallbackHeight() {
    for missing: [Window]? in [[], nil] {
      var scene = scene()
      _ = scene.handle(sample([menu(depth: 37)]))
      _ = scene.handle(sample(missing))
      XCTAssertEqual(scene.bandFrames[1]?.height, 37)
      _ = scene.handle(sample(missing))
      XCTAssertEqual(scene.bandFrames[1]?.height, 33)
    }
  }

  func testKeyPlateUsesTheConfirmedDepthAcrossMissingSamples() throws {
    let screen = display()
    var scene = scene()
    for windows: [Window]? in [[menu(depth: 37)], [menu()], nil] {
      _ = scene.handle(sample(windows))
      let plan = try menuHeightPlan(scene, on: screen)
      XCTAssertEqual(plan.key.plate?.flipped.minY, 29.5)
      XCTAssertEqual(plan.key.calibratedPlate?.flipped.minY, 33)
    }
  }

  func testEntranceMasksTheEdgeWhenTheNotchExtendsBelowTheMenu() throws {
    let screen = display()
    var scene = scene()
    _ = scene.handle(sample([menu(depth: 31)]))
    scene.startPreview(displays: [screen])
    scene.advanceEntrance(display: 1, elapsedMS: 180)
    let plan = try menuHeightPlan(scene, on: screen)
    let band = try XCTUnwrap(plan.band.frame)
    let edge = try XCTUnwrap(plan.edge.frame)
    XCTAssertEqual(edge.height, 1)
    XCTAssertNotEqual(plan.band.mask, .none)
    XCTAssertEqual(plan.edge.mask, BarEntranceMask.edge(band: plan.band.mask, bandFrame: band, edgeFrame: edge))
  }

  private func menuHeightScreen(gap: CGFloat, safeArea: CGFloat) -> BarDisplay {
    let screen = display()
    var visible = screen.frame
    visible.size.height -= gap
    return BarDisplay(id: screen.id, frame: screen.frame, visibleFrame: visible, safeAreaTop: safeArea,
                      scale: screen.scale, notchWidth: screen.notchWidth, isBuiltin: screen.isBuiltin)
  }

  private func menuHeightPlan(_ scene: BarScene, on screen: BarDisplay) throws -> BarDisplayPlan {
    let plan = BarSurface.plan(geometry: [screen.id: screen], scene: scene,
                               entrance: scene.entrances, settings: settings)
    return try XCTUnwrap(plan.displays[screen.id])
  }
}
