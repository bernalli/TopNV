import XCTest
@testable import TopNVCore

extension BarSceneTests {
  func testSystemMenuBackgroundClosesBandEdgeAndKeysEvenWithoutWindowEvidence() throws {
    let screen = display()
    var scene = scene()
    _ = scene.handle(sample([menu(depth: 31)]))
    let creation = try XCTUnwrap(scene.keyDecisions[1]?.create)
    let old = BarKeyCreation(instance: scene.keyInstances[1] ?? 0, reservation: creation)
    XCTAssertTrue(scene.keyCommitted(old, window: 101, display: 1))
    func currentPlan() throws -> BarDisplayPlan {
      try XCTUnwrap(BarSurface.plan(geometry: [1: screen], scene: scene,
                                    entrance: scene.entrances, settings: settings).displays[1])
    }
    XCTAssertNotNil(try currentPlan().edge.frame)
    scene.startPreview(displays: [screen])
    let changed = scene.handle(sample(nil, active: [1: [101]], menuBarBackground: true))
    XCTAssertEqual(changed.menuBarBackgroundChange, true)
    XCTAssertTrue(changed.traces.contains("System menu bar background enabled=true"))
    for windows: [Window]? in [nil, [menu()], [menu(), background(19)]] {
      let repeated = scene.handle(sample(windows, active: [1: [101]], menuBarBackground: true))
      XCTAssertNil(repeated.menuBarBackgroundChange)
      XCTAssertFalse(repeated.traces.contains { $0.hasPrefix("System menu bar background") })
      scene.startPreview(displays: [screen])
      let plan = try currentPlan()
      XCTAssertFalse(plan.bandEnabled)
      XCTAssertFalse(plan.band.exists)
      XCTAssertFalse(plan.edge.exists)
      XCTAssertFalse(plan.key.exists)
      XCTAssertNil(plan.key.create)
      XCTAssertEqual(plan.blackBottom, 0)
      XCTAssertEqual(Set(plan.corners.keys), Set(ScreenCorner.allCases))
      XCTAssertTrue(plan.corners.values.allSatisfy(\.exists))
      XCTAssertNil(scene.entrances[1])
    }
    let restored = scene.handle(sample([menu()], now: 5))
    XCTAssertEqual(restored.menuBarBackgroundChange, false)
    XCTAssertTrue(restored.traces.contains("System menu bar background enabled=false"))
    XCTAssertTrue(try currentPlan().band.exists)
    XCTAssertNotNil(try currentPlan().key.create)
  }

  func testSystemMenuBackgroundKeepsSamplingWithCornersOffAndHonorsHideNotchOff() {
    let screen = display()
    var scene = BarScene()
    for enabled in [true, false] {
      let settings = BarSettings(hideNotch: enabled, roundCorners: false, cornersOnAllDisplays: false)
      _ = scene.handle(.screenConfigurationChanged, displays: [screen], settings: settings,
                       entrance: .settings, screenRebuildPending: false)
      _ = scene.handle(sample([menu()], menuBarBackground: true))
      XCTAssertEqual(scene.needsSamples, enabled)
      XCTAssertTrue(scene.bandFrames.isEmpty)
      _ = scene.handle(sample([menu()]))
      XCTAssertEqual(scene.bandFrames[1] != nil, enabled)
    }
  }
}

extension MenuLayoutTests {
  func testSystemMenuBackgroundExplainsThePausedBandOnlyWhenRequested() {
    var state = MenuState(hideNotch: true, roundCorners: true, cornersOnAllDisplays: false,
                          launchAtLogin: false, loginNeedsApproval: false, loginError: nil,
                          updates: .hidden, isTestCopy: true)
    for background in [false, true] {
      state.menuBarBackground = background
      let rows = MenuLayout.rows(for: state, localizer: .english)
      let caption = rows.filter { $0.id.hasPrefix("hideNotch.caption.") }
      XCTAssertEqual(!caption.isEmpty, background)
      XCTAssertTrue(caption.allSatisfy { $0.kind == .info })
      if let preview = rows.first(where: { $0.id == "animationPreview" }),
         case let .submenu(_, enabled) = preview.kind { XCTAssertEqual(enabled, !background) }
    }
    state.hideNotch = false
    XCTAssertFalse(MenuLayout.rows(for: state).contains { $0.id.hasPrefix("hideNotch.caption.") })
  }
}
