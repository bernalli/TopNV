import CoreGraphics
import XCTest
@testable import TopNVCore

final class BarSceneTests: XCTestCase {
  private typealias Window = MenuBarEvidence.Window
  private var seed: UInt64 = 0xBA12
  private let settings = BarSettings(hideNotch: true, roundCorners: true, cornersOnAllDisplays: true)

  private func display(_ id: UInt32 = 1, hiddenMenu: Bool = false) -> BarDisplay {
    let frame = CGRect(x: CGFloat(id - 1) * 1800, y: 0, width: 1512, height: 982)
    let visible = CGRect(x: frame.minX, y: 0, width: frame.width, height: hiddenMenu ? 982 : 949)
    return BarDisplay(id: id, frame: frame, visibleFrame: visible, safeAreaTop: 32,
                      scale: 2, notchWidth: 180, isBuiltin: id == 1)
  }

  private func menu(_ id: UInt32 = 1) -> Window {
    let frame = display(id).frame
    return Window(owner: .windowServer, layer: 24,
                  bounds: CGRect(x: frame.minX, y: frame.maxY - 33, width: frame.width, height: 33))
  }

  private func background(_ layer: Int, _ id: UInt32 = 1, offset: CGFloat = 0, alpha: Double = 1) -> Window {
    Window(owner: .desktop, layer: layer, bounds: display(id).frame.offsetBy(dx: offset, dy: 0),
           isWindowManager: true, alpha: alpha, number: id + 100)
  }

  private func scene(_ displays: [BarDisplay]? = nil) -> BarScene {
    var scene = BarScene()
    _ = scene.handle(.screenConfigurationChanged, displays: displays ?? [display()], settings: settings,
                     entrance: .system, screenRebuildPending: false)
    scene.endEvent(screenRebuildPending: false)
    return scene
  }

  private func sample(_ windows: [Window]?, _ displays: [BarDisplay]? = nil, now: Double = 1,
                      active: [UInt32: [Int]] = [:], fullScreen: Bool = false, reduced: Bool = false) -> BarSample {
    BarSample(displays: displays ?? [display()], windows: windows, systemFullScreen: fullScreen,
              appearance: [1: .light, 2: .light], activeKeyWindows: active, now: now,
              reduceMotion: reduced, signalTime: now + 100)
  }

  private func creation(_ scene: BarScene, _ id: UInt32 = 1) throws -> BarKeyCreation {
    BarKeyCreation(instance: scene.keyInstances[id] ?? 0, reservation: try XCTUnwrap(scene.keyDecisions[id]?.create))
  }

  func testSceneKindPerDisplayFollowsTheClassifier() throws {
    let slide = background(-1, offset: 240), native = Window(owner: .application, layer: 0,
      bounds: display().visibleFrame, isFrontmostApp: true)
    // Settled active windows from the characterization table. The first ID survives duplicates.
    struct Fixture {
      let windows: [Window]?
      let kind: BarSceneKind
      let gate: Bool?
      var closed = [9]
    }
    let fixtures: [Fixture] = [
      .init(windows: [menu()], kind: .desktop, gate: true),
      .init(windows: [menu(), background(18), slide], kind: .revealed, gate: false),
      .init(windows: [menu(), background(19), native], kind: .overview, gate: nil, closed: [8, 9]),
      .init(windows: [native, menu()], kind: .fullScreen, gate: nil, closed: [8, 9]),
      .init(windows: nil, kind: .unknown, gate: false),
      .init(windows: [menu(), background(MenuBarEvidence.fullScreenBackdropLayer)], kind: .fullScreen, gate: true)
    ]
    for fixture in fixtures {
      let both = [display(), display(2)]
      var scene = scene(both)
      let windows = fixture.windows.map { $0 + [menu(2)] }
      _ = scene.handle(sample(windows, both, active: [1: [9, 8, 8]], fullScreen: true))
      XCTAssertEqual(scene.kinds[1], fixture.kind)
      XCTAssertEqual(scene.kinds[2], windows == nil ? .unknown : .desktop)
      let decision = try XCTUnwrap(scene.keyDecisions[1])
      XCTAssertEqual(decision.close, fixture.closed)
      XCTAssertEqual(decision.gates[8], fixture.gate)
      XCTAssertEqual(scene.visibility[1], fixture.kind != .overview && fixture.kind != .revealed)
    }

    var sliding = scene()
    for time in [1.0, 7] {
      _ = sliding.handle(sample([menu(), slide], now: time, active: [1: [8]]))
    }
    XCTAssertEqual(sliding.kinds[1], .sliding)
    XCTAssertEqual(sliding.keyDecisions[1]?.gates, [8: true])

    let both = [display(1, hiddenMenu: true), display(2)]
    var attributed = scene(both)
    _ = attributed.handle(sample([background(-1), background(MenuBarEvidence.fullScreenBackdropLayer, 2)],
                                 both, fullScreen: true))
    XCTAssertEqual(attributed.kinds, [1: .desktop, 2: .fullScreen])
    XCTAssertNil(attributed.evidence(display: 1)?.menuEdgeFrame)
  }

  func testRevealHidesBandAndCornersAndTheReturnStartsTheEntrance() throws {
    var scene = scene()
    let first = scene.handle(sample([menu()]))
    XCTAssertTrue(first.traces.contains("Desktop overlays, display 1: visible=true"))
    let ticket = try creation(scene)
    XCTAssertTrue(scene.keyCommitted(ticket, window: 4, display: 1))
    let active = sample([menu()], active: [1: [4]])
    let trace = "Keyed menu bar, display 1: appearance=light context=desktop menu=true revealed=false "
      + "surface=-1 systemFullScreen=false nativeFullScreen=false backdrop=false sliding=false gate=true "
      + "list=true active=1 windows=1 close=0 create=false"
    XCTAssertEqual(scene.handle(active).traces, [trace])
    XCTAssertTrue(scene.handle(active).traces.isEmpty)
    _ = scene.handle(sample([menu(), background(19)], active: [1: [4]]))
    XCTAssertEqual(scene.visibility[1], false)
    XCTAssertEqual(scene.keyDecisions[1]?.gates, [4: false])
    XCTAssertNil(scene.evidence(display: 1)?.menuEdgeFrame)
    let start = scene.handle(sample([menu(), background(19, alpha: 0.8)], now: 2, active: [1: [4]]))
    XCTAssertEqual(scene.entrances[1]?.origin, .returnSignal)
    XCTAssertEqual(scene.entrances[1]?.elapsedMS, 0)
    XCTAssertEqual(start.entranceEffects, [.start(display: 1, returnSignal: 102)])
    XCTAssertEqual(scene.keyDecisions[1]?.gates, [4: true])
    // The display link already restored the presentation after a timeout.
    scene.finishEntrance(display: 1)
    let late = scene.handle(sample([menu()], now: 3, active: [1: [4]]))
    XCTAssertEqual(late.entranceEffects, [.surfaceEnded(display: 1, signalTime: 103)])
    XCTAssertTrue(scene.entrances.isEmpty)
    XCTAssertTrue(scene.handle(sample([menu()], now: 4, active: [1: [4]])).entranceEffects.isEmpty)
  }

  func testASpaceChangeIsNotATopologyChangeForBandOrCorners() {
    var scene = scene([display(), display(2)])
    let frames = scene.bandFrames
    scene.systemNotification(.space, uptime: 2)
    let space = scene.handle(.spaceChanged, displays: [display(2)], settings: settings,
                             entrance: .system, screenRebuildPending: false)
    XCTAssertTrue(space.cancelAll)
    XCTAssertTrue(space.closeCorners.isEmpty && space.closeBands.isEmpty)
    XCTAssertEqual(scene.bandFrames, frames)
    XCTAssertEqual(scene.cornerDisplays, [1, 2])
    let screen = scene.handle(.screenConfigurationChanged, displays: [display(2)], settings: settings,
                              entrance: .system, screenRebuildPending: false)
    XCTAssertEqual(screen.closeCorners, [1])
    XCTAssertEqual(screen.closeBands, [1])
    XCTAssertEqual(scene.cornerDisplays, [2])
    XCTAssertNil(scene.bandFrames[1])
  }

  func testSettingsActivationStartsOneEntrance() {
    var scene = BarScene()
    let off = BarSettings(hideNotch: false, roundCorners: true, cornersOnAllDisplays: false)
    _ = scene.handle(.screenConfigurationChanged, displays: [display(), display(2)], settings: off,
                     entrance: .settings, screenRebuildPending: false)
    _ = scene.handle(sample([menu(), background(18)]))
    XCTAssertEqual(scene.visibility[1], false)
    XCTAssertEqual(scene.cornerDisplays, [1])
    XCTAssertTrue(scene.needsSamples)
    XCTAssertFalse(scene.keyedActive)
    _ = scene.handle(.settingsChanged, displays: [display()], settings: settings,
                     entrance: .settings, screenRebuildPending: false)
    let first = scene.handle(sample([menu()]))
    XCTAssertTrue(first.entranceEffects.contains(.start(display: 1, returnSignal: nil)))
    XCTAssertEqual(scene.entrances[1]?.origin, .settings)
    XCTAssertEqual(scene.entrances[1]?.durationMS, BarAnimation.calm.durationMS(rounded: true))
    scene.advanceEntrance(display: 1, elapsedMS: 30)
    scene.advanceEntrance(display: 1, elapsedMS: .nan)
    XCTAssertEqual(scene.entrances[1]?.elapsedMS, 30)
    scene.endEvent(screenRebuildPending: false)
    scene.finishEntrance(display: 1)
    _ = scene.handle(sample([menu()]))
    XCTAssertTrue(scene.entrances.isEmpty)
  }

  func testKeyFailureClosesKeysForTheSessionAndLeavesTheOtherParts() throws {
    let both = [display(), display(2)]
    var scene = scene(both)
    _ = scene.handle(sample([menu(), menu(2)], both))
    let old = try creation(scene, 2)
    for id in [UInt32(1), 2] {
      let reserved = try creation(scene, id)
      XCTAssertTrue(scene.keyCommitted(reserved, window: Int(id), display: id))
    }
    let active: [UInt32: [Int]] = [1: [1], 2: [2]]
    _ = scene.handle(sample([menu(), menu(2)], both, active: active))
    XCTAssertEqual(scene.keyDecisions[2]?.gates, [2: true])
    scene.keyDidFail()
    XCTAssertTrue(scene.keyFailed)
    XCTAssertFalse(scene.keyedActive)
    XCTAssertTrue(scene.keyStates.isEmpty && scene.keyDecisions.isEmpty)
    XCTAssertFalse(scene.keyCommitted(old, window: 4, display: 2))
    _ = scene.handle(.settingsChanged, displays: both, settings: settings,
                     entrance: .settings, screenRebuildPending: false)
    _ = scene.handle(sample([menu(), menu(2), background(18)], both, active: active))
    XCTAssertTrue(scene.keyDecisions.isEmpty)
    XCTAssertEqual(scene.visibility, [1: false, 2: true])
    XCTAssertEqual(scene.cornerDisplays, [1, 2])
    XCTAssertEqual(Set(scene.bandFrames.keys), [1, 2])
    XCTAssertNotNil(scene.evidence(display: 2)?.menuEdgeFrame)
  }

  func testAnAdapterResetGivesTheDisplayAFullCreationBudget() throws {
    var scene = scene()
    _ = scene.handle(sample([menu()]))
    let old = try creation(scene)
    scene.keyWindowsReset(display: 1)
    for window in 1...3 {
      _ = scene.handle(sample([menu()], now: Double(window)))
      let fresh = try creation(scene)
      XCTAssertNotEqual(fresh.instance, old.instance)
      if window == 1 { XCTAssertEqual(fresh.reservation, old.reservation) }
      XCTAssertFalse(scene.keyCommitted(old, window: 90, display: 1))
      scene.consumeKeyDecisions()
      XCTAssertTrue(scene.keyDecisions.isEmpty)
      XCTAssertTrue(scene.keyCommitted(fresh, window: window, display: 1))
      XCTAssertFalse(scene.keyCommitted(fresh, window: window, display: 1))
      scene.keyClosed(window: window, display: 1)
    }
    _ = scene.handle(sample([menu()], now: 5))
    XCTAssertNil(scene.keyDecisions[1]?.create)
    _ = scene.handle(.screenConfigurationChanged, displays: [], settings: settings, entrance: .system,
                     screenRebuildPending: false)
    XCTAssertFalse(scene.needsSamples)
    _ = scene.handle(.screenConfigurationChanged, displays: [display()], settings: settings, entrance: .system,
                     screenRebuildPending: false)
    _ = scene.handle(sample([menu()], now: 6))
    XCTAssertGreaterThan(try creation(scene).instance, old.instance + 1)
  }

  func testAnEntranceIsCancelledByAnyNonDesktopSceneSpaceChangeScreenChangeOrReduceMotion() {
    let interruptions = [
      sample([menu(), background(18)]), sample([menu(), background(19)]),
      sample([menu(), Window(owner: .application, layer: 0, bounds: display().frame)]),
      sample([menu(), background(-1, offset: 240)]), sample(nil), sample([], []), sample([menu()], reduced: true)
    ]
    for interruption in interruptions {
      var scene = scene()
      _ = scene.handle(sample([menu(), background(18)]))
      _ = scene.handle(sample([menu()]))
      XCTAssertEqual(scene.entrances[1]?.origin, .returnSignal)
      let effects = scene.handle(interruption)
      XCTAssertTrue(effects.entranceEffects.contains(.restore(display: 1)))
      XCTAssertTrue(scene.entrances.isEmpty)
    }
    for kind in [BarSystemNotification.space, .screen] {
      var scene = scene()
      _ = scene.handle(sample([menu()]))
      scene.startPreview(displays: [display()])
      scene.systemNotification(kind, uptime: 2)
      XCTAssertTrue(scene.entrances.isEmpty)
    }
  }

  func testAPreviewIsCancelledWhenItIsNoLongerPermitted() {
    var scene = scene()
    _ = scene.handle(sample([menu()]))
    scene.startPreview(displays: [display()])
    XCTAssertEqual(scene.entrances[1]?.origin, .preview)
    XCTAssertEqual(scene.entrances[1]?.elapsedMS, -600)
    _ = scene.handle(sample([menu()], active: [1: [42]]))
    XCTAssertEqual(scene.entrances[1]?.elapsedMS, -600)
    let hidden = [display(1, hiddenMenu: true)]
    let interrupted = scene.handle(sample([background(-1)], hidden))
    XCTAssertEqual(scene.kinds[1], .desktop)
    XCTAssertTrue(interrupted.entranceEffects.contains(.restore(display: 1)))
    XCTAssertTrue(scene.entrances.isEmpty)
    scene.startPreview(displays: hidden)
    XCTAssertTrue(scene.entrances.isEmpty)
    _ = scene.handle(sample([menu()], reduced: true))
    scene.startPreview(displays: [display()])
    XCTAssertTrue(scene.entrances.isEmpty)
  }

  func testFastSamplingOnlyDuringARevealOrItsReturn() {
    var scene = scene()
    for (windows, fast) in [([menu()], false), ([menu(), background(19)], true),
                            ([menu(), background(19, alpha: 0.8)], true), ([menu()], false),
                            ([menu(), background(-1, offset: 300)], false)] {
      XCTAssertEqual(scene.handle(sample(windows)).wantsFastSamples, fast)
    }
    XCTAssertFalse(scene.handle(sample(nil)).wantsFastSamples)
  }
}

// MARK: - Hostile deliveries and callbacks

extension BarSceneTests {
  func testRepeatedNotificationsNeverResetTheCreationBudget() throws {
    var scene = scene()
    for visit in 1...5 {
      let now = Double(visit) * 10
      _ = scene.handle(sample([menu()], now: now))
      let pending = visit <= 3 ? try creation(scene) : nil
      if visit > 3 { XCTAssertNil(scene.keyDecisions[1]?.create) }
      scene.systemNotification(.space, uptime: now + 1)
      _ = scene.handle(.spaceChanged, displays: [display()], settings: settings, entrance: .system,
                       screenRebuildPending: false)
      if let pending { XCTAssertFalse(scene.keyCommitted(pending, window: visit, display: 1)) }
      _ = scene.handle(sample([menu()], now: now + 1.49))
      XCTAssertNil(scene.keyDecisions[1]?.create)
      scene.endEvent(screenRebuildPending: false)
      XCTAssertEqual(scene.keyStates[1]?.creationsThisVisit, min(visit, 3))
    }
  }

  func testMissingSamplesHoldTheLastVisibility() throws {
    func document(_ originX: CGFloat) -> Window {
      Window(owner: .application, layer: 0, bounds: CGRect(x: originX, y: 120, width: 500, height: 600), number: 44)
    }
    var scene = scene()
    _ = scene.handle(sample([menu(), document(300)]))
    let pending = try creation(scene)
    XCTAssertTrue(scene.keyCommitted(pending, window: 8, display: 1))
    let active: [UInt32: [Int]] = [1: [8]]
    _ = scene.handle(sample([menu(), document(300)], active: active))
    let frame = scene.bandFrames[1]
    _ = scene.handle(sample([menu(), document(-496), background(18)], active: active))
    // A skipped delivery cannot consume the tracker's one missing-surface allowance.
    scene.consumeKeyDecisions()
    scene.advanceEntrance(display: 1, elapsedMS: 100)
    XCTAssertEqual(scene.visibility[1], false)
    XCTAssertEqual(scene.kinds[1], .revealed)
    _ = scene.handle(sample([menu(), document(-496)], active: active))
    XCTAssertEqual(scene.kinds[1], .revealed)
    XCTAssertNil(scene.evidence(display: 1)?.revealLayer)
    let instance = scene.keyInstances[1]
    _ = scene.handle(sample([], [], active: active))
    XCTAssertEqual(scene.kinds[1], .absent)
    XCTAssertEqual(scene.visibility[1], false)
    XCTAssertNil(scene.evidence(display: 1))
    XCTAssertEqual(scene.keyInstances[1], instance)
    XCTAssertEqual(scene.keyStates[1]?.visibility, [8: false])
    XCTAssertEqual(scene.bandFrames[1], frame)
    XCTAssertNil(scene.keyDecisions[1])
    _ = scene.handle(sample(nil, active: active))
    XCTAssertEqual(scene.kinds[1], .unknown)
    XCTAssertEqual(scene.visibility[1], true)
    XCTAssertEqual(scene.keyDecisions[1]?.gates, [8: false])
    XCTAssertTrue(scene.entrances.isEmpty)
  }

  func testARevealAcrossASpaceSwitchNeverReplaysTheEntrance() throws {
    for sampleFirst in [true, false] {
      var scene = scene()
      _ = scene.handle(sample([menu(), background(18)]))
      if sampleFirst {
        _ = scene.handle(sample([menu()], now: 3))
        XCTAssertEqual(scene.entrances[1]?.origin, .returnSignal)
      }
      scene.systemNotification(.space, uptime: 4)
      _ = scene.handle(.spaceChanged, displays: [display()], settings: settings, entrance: .system,
                       screenRebuildPending: false)
      _ = scene.handle(sample(sampleFirst ? [menu(), background(18)] : [menu()], now: 4))
      XCTAssertTrue(scene.entrances.isEmpty)
      scene.endEvent(screenRebuildPending: false)
      _ = scene.handle(sample([menu()], now: 4.1))
      XCTAssertTrue(scene.entrances.isEmpty)
      XCTAssertNil(scene.keyDecisions[1]?.create)
      _ = scene.handle(sample([menu()], now: 4.5))
      _ = try creation(scene)
    }
  }

  func testAScreenChangeDuringAnEntranceCancelsItAndKeepsTheBand() throws {
    var scene = scene()
    _ = scene.handle(sample([menu(), background(18)]))
    _ = scene.handle(sample([menu()], now: 2))
    let pending = try creation(scene)
    let frame = scene.bandFrames[1]
    scene.advanceEntrance(display: 1, elapsedMS: 91)
    scene.systemNotification(.screen, uptime: 2.1)
    scene.advanceEntrance(display: 1, elapsedMS: 92)
    XCTAssertTrue(scene.entrances.isEmpty)
    XCTAssertEqual(scene.bandFrames[1], frame)
    XCTAssertTrue(scene.keyCommitted(pending, window: 7, display: 1))
    _ = scene.handle(.settingsChanged, displays: [display()], settings: settings, entrance: .settings,
                     screenRebuildPending: true)
    scene.endEvent(screenRebuildPending: true)
    _ = scene.handle(sample([menu(), background(18)], active: [1: [7]]))
    _ = scene.handle(sample([menu()], active: [1: [7]]))
    XCTAssertEqual(scene.entranceEvent, .system)
    XCTAssertTrue(scene.entrances.isEmpty)
    _ = scene.handle(.screenConfigurationChanged, displays: [display()], settings: settings,
                     entrance: .system, screenRebuildPending: false)
    _ = scene.handle(sample([menu()], active: [1: [7]]))
    scene.endEvent(screenRebuildPending: false)
    XCTAssertEqual(scene.bandFrames[1], frame)
    XCTAssertEqual(scene.entranceEvent, .sample)
    XCTAssertEqual(scene.keyDecisions[1]?.gates, [7: true])
  }
}

// MARK: - Generated histories

extension BarSceneTests {
  private func checkInvariants(_ subject: BarScene, label: String) {
    for (id, entrance) in subject.entrances {
      XCTAssertEqual(subject.kinds[id], .desktop, label)
      XCTAssertNotNil(subject.bandFrames[id], label)
      XCTAssertTrue(entrance.elapsedMS.isFinite, label)
    }
    for (id, state) in subject.keyStates {
      XCTAssertNotNil(subject.bandFrames[id], label)
      XCTAssertFalse(subject.keyFailed, label)
      XCTAssertLessThanOrEqual(state.creationsThisVisit, 3, label)
    }
  }

  private func checkKeyDecisions(_ input: BarSample, before: [UInt32: KeyedOverlayState], scene: BarScene,
                                 effects: BarSampleEffects, label: String) {
    // Independent composition of the raw fixture and the characterized per-display key.
    for screen in input.displays where scene.keyedActive {
      guard let band = scene.bandFrames[screen.id] else { continue }
      let raw = MenuBarEvidence.evaluate(frame: screen.frame, visibleFrame: screen.visibleFrame,
        bandFrame: band, windows: input.windows, systemFullScreen: input.systemFullScreen,
        displayFrames: input.displays.map(\.frame))
      var reference = before[screen.id] ?? KeyedOverlayState()
      let expected = reference.update(.init(
        activeWindowIDs: input.activeKeyWindows[screen.id] ?? [], appearance: .light, context: raw.context,
        menuVisible: raw.menuVisible, enabled: true, now: input.now,
        desktopRevealed: raw.desktopRevealed, spaceSliding: raw.spaceSliding, nativeFullScreen: raw.nativeFullScreen))
      let actual = effects.keyDecisions[screen.id]
      XCTAssertEqual(actual?.close, expected.close, label)
      XCTAssertEqual(actual?.gates, expected.gates, label)
      XCTAssertEqual(actual?.create, expected.create, label)
    }
  }

  private func next(_ bound: Int) -> Int {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Int((seed >> 33) % UInt64(bound))
  }

  private func windows(_ id: UInt32) -> [Window] {
    switch next(7) {
    case 0: return [menu(id), background(18, id)]
    case 1: return [menu(id), background(19, id)]
    case 2: return [menu(id), background(-1, id, offset: 220)]
    case 3: return [Window(owner: .application, layer: 0, bounds: display(id).frame, isFrontmostApp: true)]
    case 4: return [background(-1, id)]
    default: return [menu(id)]
    }
  }

  // The two histories receive the same global events. Only display 2's windows differ.
  private struct History {
    var screens: [BarDisplay]
    var options: BarSettings
    var subject: BarScene
    var neighbour: BarScene
    var tickets: [(UInt32, BarKeyCreation)] = []
  }

  private func deliverSample(_ history: inout History, now: Double, label: String) {
    let local = windows(1), other = windows(2), alternate = windows(2)
    let unavailable = next(9) == 0, reduced = next(8) == 0, full = next(5) == 0
    let present = history.screens.filter { _ in next(6) != 0 }
    var active: [UInt32: [Int]] = [:]
    for id in history.subject.keyStates.keys.sorted() {
      active[id] = history.subject.keyStates[id]?.visibility.keys.sorted().filter { _ in next(2) == 0 }
    }
    let input = sample(unavailable ? nil : local + other, present, now: now, active: active, fullScreen: full,
                       reduced: reduced)
    let before = history.subject.keyStates
    let effects = history.subject.handle(input)
    _ = history.neighbour.handle(sample(unavailable ? nil : local + alternate, present, now: now, active: active,
                                        fullScreen: full, reduced: reduced))
    checkKeyDecisions(input, before: before, scene: history.subject, effects: effects, label: label)
    for (id, decision) in effects.keyDecisions.sorted(by: { $0.key < $1.key }) {
      if let reservation = decision.create {
        let ticket = BarKeyCreation(instance: history.subject.keyInstances[id] ?? 0, reservation: reservation)
        history.tickets.append((id, ticket))
      }
    }
    history.subject.endEvent(screenRebuildPending: false)
    history.neighbour.endEvent(screenRebuildPending: false)
  }

  private func rebuild(_ history: inout History, event: BandState.Event, now: Double) {
    switch event {
    case .spaceChanged:
      history.subject.systemNotification(.space, uptime: now)
      history.neighbour.systemNotification(.space, uptime: now)
    case .screenConfigurationChanged:
      history.subject.systemNotification(.screen, uptime: now)
      history.neighbour.systemNotification(.screen, uptime: now)
      history.screens = [display(), display(2)].filter { _ in next(3) != 0 }
    case .settingsChanged:
      history.options = BarSettings(hideNotch: !history.options.hideNotch, roundCorners: next(3) != 0,
                                    cornersOnAllDisplays: true)
    }
    let entrance: BandEntrance.Event = event == .settingsChanged ? .settings : .system
    history.subject.handle(event, displays: history.screens, settings: history.options,
                           entrance: entrance, screenRebuildPending: false)
    history.neighbour.handle(event, displays: history.screens, settings: history.options,
                             entrance: entrance, screenRebuildPending: false)
    deliverSample(&history, now: now, label: "synchronous rebuild sample")
  }

  private func deliverCallback(_ history: inout History, window: Int, label: String) {
    guard !history.tickets.isEmpty else { return }
    let (target, ticket) = history.tickets[next(history.tickets.count)]
    let accepted = history.subject.keyCommitted(ticket, window: window, display: target)
    let peerAccepted = history.neighbour.keyCommitted(ticket, window: window, display: target)
    if target == 1 { XCTAssertEqual(accepted, peerAccepted, label) }
    if ticket.instance != (history.subject.keyInstances[target] ?? 0) { XCTAssertFalse(accepted, label) }
  }

  func testRandomEventSequencesKeepTheTableInvariants() {
    let events: [BandState.Event] = [.spaceChanged, .screenConfigurationChanged, .settingsChanged]
    for sequence in 0..<300 {
      let screens = [display(), display(2)]
      var history = History(screens: screens, options: settings, subject: scene(screens), neighbour: scene(screens))
      var now = 0.0
      for step in 0..<60 {
        let label = "sequence \(sequence), step \(step)"
        now += next(6) == 0 ? -1 : 0.6
        let uptime = next(17) == 0 ? Double.nan : now
        let id = UInt32(next(2) + 1)
        let action = next(16)
        switch action {
        case 0...2: rebuild(&history, event: events[action], now: uptime)
        case 3:
          history.subject.keyWindowsReset(display: id)
          history.neighbour.keyWindowsReset(display: id)
        case 4: deliverCallback(&history, window: step, label: label)
        case 5:
          history.subject.keyClosed(window: -1, display: id)
          history.neighbour.keyClosed(window: -1, display: id)
        case 6 where step > 40:
          history.subject.keyDidFail()
          history.neighbour.keyDidFail()
        case 7:
          history.subject.startPreview(displays: history.screens)
          history.neighbour.startPreview(displays: history.screens)
        default: deliverSample(&history, now: uptime, label: label)
        }
        let subject = history.subject, peer = history.neighbour
        checkInvariants(subject, label: label)
        XCTAssertEqual(subject.kinds[1], peer.kinds[1], label)
        XCTAssertEqual(subject.visibility[1], peer.visibility[1], label)
        XCTAssertEqual(subject.entrances[1], peer.entrances[1], label)
        XCTAssertEqual(subject.keyStates[1]?.visibility, peer.keyStates[1]?.visibility, label)
        XCTAssertEqual(subject.keyStates[1]?.creationsThisVisit, peer.keyStates[1]?.creationsThisVisit, label)
      }
    }
  }
}
