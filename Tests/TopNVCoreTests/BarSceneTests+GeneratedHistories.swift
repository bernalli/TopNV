import CoreGraphics
import XCTest
@testable import TopNVCore

extension BarSceneTests {
  private func checkInvariants(_ subject: BarScene, label: String) {
    for (id, entrance) in subject.entrances {
      XCTAssertTrue(subject.entrancePermitted(display: id), label)
      XCTAssertNotNil(subject.bandFrames[id], label)
      XCTAssertTrue(entrance.elapsedMS.isFinite, label)
    }
    for (id, state) in subject.keyStates {
      XCTAssertNotNil(subject.bandFrames[id], label)
      XCTAssertFalse(subject.keyFailed, label)
      XCTAssertLessThanOrEqual(state.creationsThisVisit, 3, label)
    }
  }

  private func checkKeyDecisions(_ input: BarSample, resolved: [UInt32: MenuBarEvidence.Result],
                                 before: [UInt32: KeyedOverlayState], scene: BarScene,
                                 effects: BarSampleEffects, label: String) {
    // Independent composition of the raw fixture, DesktopReturn and the characterized per-display key.
    for screen in input.displays where scene.keyedActive {
      guard let evidence = resolved[screen.id] else { continue }
      let followsSurface = evidence.fullScreenBackdrop && scene.entrances[screen.id] == nil
      let revealed = followsSurface ? evidence.revealLayer != nil : evidence.desktopRevealed
      var reference = before[screen.id] ?? KeyedOverlayState()
      let expected = reference.update(.init(
        activeWindowIDs: input.activeKeyWindows[screen.id] ?? [], appearance: .light, context: evidence.context,
        menuVisible: evidence.menuVisible, enabled: true, now: input.now,
        desktopRevealed: revealed, spaceSliding: evidence.spaceSliding,
        nativeFullScreen: evidence.nativeFullScreen))
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

  private func document(_ id: UInt32, home: Bool) -> Window {
    let frame = display(id).frame
    // Show Desktop parks a document, at its own size, outside the interior of its display.
    let originY: CGFloat = home ? 120 : frame.minY - 590
    return Window(owner: .application, layer: 0,
                  bounds: CGRect(x: frame.minX + 300, y: originY, width: 500, height: 600), number: 40 + id)
  }

  private func windows(_ id: UInt32) -> [Window] {
    let backdrop = next(3) == 0 ? [background(MenuBarEvidence.fullScreenBackdropLayer, id)] : []
    return surfaces(id) + backdrop
  }

  private func surfaces(_ id: UInt32) -> [Window] {
    switch next(10) {
    case 0: return [menu(id), background(18, id)]
    case 1: return [menu(id), background(19, id)]
    case 2: return [menu(id), background(-1, id, offset: 220)]
    case 3: return [Window(owner: .application, layer: 0, bounds: display(id).frame, isFrontmostApp: true)]
    case 4: return [background(-1, id)]
    case 5: return [menu(id), document(id, home: true)]
    case 6: return [menu(id), background(18, id), document(id, home: false)]
    case 7: return [menu(id), document(id, home: false)]
    case 8: return [menu(id), background(19, id, alpha: 0.8)]
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
    /// Mirror of the reducer's per-display DesktopReturn: reset at rebuild and on absence.
    var returns: [UInt32: DesktopReturn] = [:]
  }

  private func resolveMirror(_ history: inout History, _ input: BarSample) -> [UInt32: MenuBarEvidence.Result] {
    var resolved: [UInt32: MenuBarEvidence.Result] = [:]
    for (id, band) in history.subject.bandFrames.sorted(by: { $0.key < $1.key }) {
      guard let screen = input.displays.first(where: { $0.id == id }) else {
        history.returns[id] = nil
        continue
      }
      let raw = MenuBarEvidence.evaluate(frame: screen.frame, visibleFrame: screen.visibleFrame, bandFrame: band,
        windows: input.windows, systemFullScreen: input.systemFullScreen, displayFrames: input.displays.map(\.frame))
      if let previous = history.subject.evidence(display: id), previous.fullScreenBackdrop != raw.fullScreenBackdrop {
        history.returns[id] = nil
      }
      resolved[id] = history.returns[id, default: DesktopReturn()].resolve(raw, on: screen.frame,
                                                                         windows: input.windows)
    }
    return resolved
  }

  private func checkBackdropTransitions(_ previous: BarScene, _ current: BarScene,
                                        effects: BarSampleEffects, label: String) {
    for id in current.bandFrames.keys {
      guard let evidence = current.evidence(display: id), evidence.context != .unknown else { continue }
      if evidence.fullScreenBackdrop, let layer = evidence.revealLayer, current.entrances[id] == nil {
        XCTAssertEqual(current.kinds[id], layer == 19 ? .overview : .revealed, label)
      }
      guard previous.entranceEvent != .system, let old = previous.evidence(display: id), old.context != .unknown,
            old.fullScreenBackdrop != evidence.fullScreenBackdrop else { continue }
      XCTAssertNil(current.entrances[id], label)
      XCTAssertTrue(effects.entranceEffects.contains(.restore(display: id)), label)
      for effect in effects.entranceEffects {
        if case let .surfaceEnded(display, _) = effect { XCTAssertNotEqual(display, id, label) }
      }
    }
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
    let before = history.subject
    let resolved = resolveMirror(&history, input)
    let effects = history.subject.handle(input)
    _ = history.neighbour.handle(sample(unavailable ? nil : local + alternate, present, now: now, active: active,
                                        fullScreen: full, reduced: reduced))
    checkBackdropTransitions(before, history.subject, effects: effects, label: label)
    checkKeyDecisions(input, resolved: resolved, before: before.keyStates, scene: history.subject, effects: effects,
                      label: label)
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
    history.returns.removeAll()
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
