import CoreGraphics
import XCTest
@testable import TopNVCore

struct BarPlanFixture {
  let display: BarDisplay
  let settings: BarSettings
  var scene: BarScene
  let geometry: [UInt32: BarDisplay]

  init(kind: BarSceneKind = .desktop, band: Bool = true, corners: Bool = true, failed: Bool = false,
       measured: Bool = true, active: [Int] = [], appearance: KeyedOverlayState.Appearance = .light) {
    let frame = CGRect(x: -1512, y: 100, width: 1512, height: 982)
    let visible = CGRect(x: -1512, y: 100, width: 1512, height: 949)
    let screen = BarDisplay(id: 1, frame: frame, visibleFrame: visible, safeAreaTop: 32,
                            scale: 2, notchWidth: 180, isBuiltin: true)
    display = screen
    settings = BarSettings(hideNotch: band, roundCorners: corners, cornersOnAllDisplays: false)
    geometry = kind == .absent ? [:] : [1: screen]
    var reducer = BarScene()
    reducer.handle(.screenConfigurationChanged, displays: [screen], settings: settings,
                   entrance: .system, screenRebuildPending: false)
    reducer.keyWindowsReset(display: 1)
    if failed { reducer.keyDidFail() }

    let menuHeight: CGFloat = band ? 33 : 1
    let menu = MenuBarEvidence.Window(owner: .windowServer, layer: measured ? 24 : 5,
      bounds: CGRect(x: frame.minX, y: frame.maxY - menuHeight, width: frame.width, height: menuHeight))
    var windows: [MenuBarEvidence.Window]? = [menu]
    switch kind {
    case .revealed, .overview:
      windows?.append(.init(owner: .desktop, layer: kind == .overview ? 19 : 18,
                            bounds: frame, isWindowManager: true))
    case .fullScreen:
      windows?.append(.init(owner: .application, layer: 0, bounds: frame))
    case .sliding:
      windows?.append(.init(owner: .desktop, layer: -1, bounds: frame.offsetBy(dx: 300, dy: 0),
                            isWindowManager: true))
    case .unknown, .absent: windows = nil
    case .desktop: break
    }
    reducer.handle(BarSample(displays: Array(geometry.values), windows: windows, systemFullScreen: false,
      appearance: [1: appearance], activeKeyWindows: [1: active], now: 1, reduceMotion: false, signalTime: 1))
    scene = reducer
  }

  func plan(elapsedMS: Double? = nil) -> BarDisplayPlan? {
    let entrance = elapsedMS.map { [UInt32(1): BarEntrance(origin: .preview, elapsedMS: $0, durationMS: 570)] }
    return BarSurface.plan(geometry: geometry, scene: scene, entrance: entrance ?? [:], settings: settings).displays[1]
  }
}

final class BarPlanTests: XCTestCase {
  func testDesktopPlanPlacesEveryPartAtItsGeometry() throws {
    let fixture = BarPlanFixture()
    let plan = try XCTUnwrap(fixture.plan())
    XCTAssertEqual(plan.kind, .desktop)
    XCTAssertTrue(plan.bandEnabled)
    let band = CGRect(x: -1512, y: 1048, width: 1512, height: 34)
    XCTAssertEqual(plan.band.frame, band)
    XCTAssertEqual(plan.key.frame, band)
    XCTAssertEqual(plan.band.pixels, PixelRect(x: 0, y: 0, width: 3024, height: 68))
    XCTAssertEqual(plan.edge.frame, CGRect(x: -1512, y: 1047, width: 1512, height: 2))
    XCTAssertEqual(plan.edge.pixels, PixelRect(x: 0, y: 66, width: 3024, height: 4))
    XCTAssertEqual(plan.blackBottom, 70)
    let frames = BarGeometry.corners(display: fixture.display.frame, bandHeight: 34, rounded: true)
    XCTAssertEqual(plan.corners.count, 4)
    for (corner, frame) in frames {
      XCTAssertEqual(plan.corners[corner]?.frame, frame)
      XCTAssertEqual(plan.corners[corner]?.pixels, BarGeometry.pixels(frame, on: fixture.display))
    }
    XCTAssertEqual(plan.key.plate, BarGeometry.plate(keySize: band.size, menuHeight: 33, scale: 2))
    let reservation = try XCTUnwrap(fixture.scene.keyDecisions[1]?.create)
    XCTAssertEqual(plan.key.create, BarKeyCreation(instance: 1, reservation: reservation))
    // The measured gap may change between rebuild and key creation.
    let screen = fixture.display
    let hiddenMenu = BarDisplay(id: 1, frame: screen.frame, visibleFrame: screen.frame, safeAreaTop: 32,
                                scale: 3, notchWidth: 180, isBuiltin: true)
    let updated = BarSurface.plan(geometry: [1: hiddenMenu], scene: fixture.scene, entrance: [:],
                                  settings: fixture.settings)
    let changed = try XCTUnwrap(updated.displays[1])
    XCTAssertEqual(changed.band.frame, band)
    XCTAssertEqual(changed.key.frame, band)
    XCTAssertEqual(changed.key.plate, BarGeometry.plate(keySize: band.size, menuHeight: 0, scale: 3))
    let unmeasured = try XCTUnwrap(BarPlanFixture(measured: false).plan())
    XCTAssertNil(unmeasured.edge.frame)
    XCTAssertEqual(unmeasured.edge.alpha, .value(0))
    XCTAssertEqual(unmeasured.blackBottom, 68)
  }

  func testRevealPlanHidesBandEdgeCornersAndKeys() throws {
    let plan = try XCTUnwrap(BarPlanFixture(kind: .revealed, active: [9, 8, 8]).plan(elapsedMS: 180))
    XCTAssertEqual(plan.kind, .revealed)
    XCTAssertEqual(plan.band.alpha, .value(0))
    XCTAssertEqual(plan.band.mask, .none)
    XCTAssertTrue(plan.edge.exists)
    XCTAssertEqual(plan.edge.alpha, .value(0))
    XCTAssertEqual(plan.corners.count, 4)
    XCTAssertTrue(plan.corners.values.allSatisfy { $0.alpha == .value(0) })
    XCTAssertEqual(plan.key.close, [9])
    XCTAssertEqual(plan.key.gates, [8: .value(0)])
    XCTAssertNil(plan.key.create)
    XCTAssertEqual(plan.blackBottom, 0)
  }

  func testHideNotchOffClosesBandKeyPlateAndEdgeButKeepsCorners() throws {
    let plan = try XCTUnwrap(BarPlanFixture(band: false).plan(elapsedMS: 180))
    XCTAssertFalse(plan.bandEnabled)
    XCTAssertFalse(plan.band.exists)
    XCTAssertFalse(plan.key.exists)
    XCTAssertNil(plan.key.plate)
    XCTAssertFalse(plan.edge.exists)
    XCTAssertEqual(plan.corners.count, 4)
    XCTAssertTrue(plan.corners.values.allSatisfy { $0.exists && $0.alpha == .value(1) })
    XCTAssertEqual(plan.corners[.topLeft]?.frame?.maxY, 1082)
  }

  func testThePlanIsDeterministic() throws {
    let fixture = BarPlanFixture()
    let second = BarDisplay(id: 2, frame: fixture.display.frame.offsetBy(dx: 1512, dy: 0),
      visibleFrame: fixture.display.visibleFrame.offsetBy(dx: 1512, dy: 0), safeAreaTop: 32,
      scale: 1, notchWidth: 140, isBuiltin: false)
    let screens = [fixture.display, second]
    var scene = fixture.scene
    scene.handle(.screenConfigurationChanged, displays: screens, settings: fixture.settings,
                 entrance: .system, screenRebuildPending: false)
    let menus = screens.map { MenuBarEvidence.Window(owner: .windowServer, layer: 24,
      bounds: CGRect(x: $0.frame.minX, y: $0.visibleFrame.maxY, width: $0.frame.width, height: 33)) }
    scene.handle(BarSample(displays: screens, windows: menus, systemFullScreen: false, appearance: [:],
                           activeKeyWindows: [:], now: 2, reduceMotion: false, signalTime: 2))
    func plan(_ order: [BarDisplay]) -> BarPlan {
      let geometry = Dictionary(uniqueKeysWithValues: order.map { ($0.id, $0) })
      let entrances = Dictionary(uniqueKeysWithValues: order.map {
        ($0.id, BarEntrance(origin: .settings, elapsedMS: Double($0.id) * 100, durationMS: 570))
      })
      return BarSurface.plan(geometry: geometry, scene: scene, entrance: entrances, settings: fixture.settings)
    }
    let first = plan(screens)
    XCTAssertEqual(Set(first.displays.keys), [1, 2])
    XCTAssertNotEqual(first.displays[1]?.band.mask, first.displays[2]?.band.mask)
    XCTAssertEqual(first, plan(screens.reversed()))
  }

  func testAnEntrancePlanMasksBandKeyAndEdgeAndFadesCorners() throws {
    let fixture = BarPlanFixture(active: [7], appearance: .dark)
    for time in [-600.0, 180, 570] {
      let plan = try XCTUnwrap(fixture.plan(elapsedMS: time))
      let band = try XCTUnwrap(plan.band.frame), edge = try XCTUnwrap(plan.edge.frame)
      let mask = BarEntranceMask.band(elapsedMS: time, bandSize: band.size, notchWidth: 180)
      XCTAssertEqual(plan.band.mask, mask)
      XCTAssertEqual(plan.band.alpha, .value(1))
      XCTAssertEqual(plan.key.mask, mask)
      XCTAssertEqual(plan.key.gates, [7: .value(0)])
      XCTAssertEqual(plan.key.backdropExtent, BarEntranceMask.keyBackdropExtent(band: mask, bandSize: band.size))
      XCTAssertEqual(plan.edge.mask, BarEntranceMask.edge(band: mask, bandFrame: band, edgeFrame: edge))
      XCTAssertEqual(plan.edge.alpha, .value(1))
      for corner in ScreenCorner.allCases {
        XCTAssertEqual(plan.corners[corner]?.alpha, .value(BarAnimation.calm.corner(at: time, top: true).progress))
      }
      XCTAssertEqual(plan.blackBottom, 0)
    }
    var departed = fixture.scene
    departed.handle(BarSample(displays: [], windows: nil, systemFullScreen: false, appearance: [:],
                              activeKeyWindows: [:], now: 2, reduceMotion: false, signalTime: 2))
    let restored = BarSurface.plan(geometry: [:], scene: departed, entrance: [:], settings: fixture.settings)
    let absent = try XCTUnwrap(restored.displays[1])
    XCTAssertEqual(absent.kind, .absent)
    XCTAssertEqual(absent.band.frame, fixture.scene.bandFrames[1])
    XCTAssertEqual(absent.band.alpha, .hold)
    XCTAssertEqual(absent.band.mask, .none)
    XCTAssertEqual(absent.key.frame, absent.band.frame)
    XCTAssertTrue(absent.key.gates.isEmpty && absent.key.close.isEmpty)
    XCTAssertNil(absent.key.create)
    XCTAssertEqual(absent.key.mask, .none)
    XCTAssertEqual(absent.edge.alpha, .value(0))
    XCTAssertEqual(absent.corners.count, 4)
    XCTAssertTrue(absent.corners.values.allSatisfy { $0.exists && $0.frame == nil && $0.alpha == .value(1) })
  }
}
