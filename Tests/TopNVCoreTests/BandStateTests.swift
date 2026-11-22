import CoreGraphics
import XCTest

@testable import TopNVCore

final class BandStateTests: XCTestCase {
  private let original = CGRect(x: 0, y: 949, width: 1512, height: 33)

  private func screen(
    id: UInt32 = 1, inset: CGFloat = 32, gap: CGFloat = 33,
    frame: CGRect = CGRect(x: 0, y: 0, width: 1512, height: 982)
  ) -> BandState.Screen {
    BandState.Screen(
      id: id, frame: frame,
      visibleFrame: CGRect(
        x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - gap),
      safeAreaTop: inset)
  }

  func testInitialConfigurationShowsTheBand() {
    var state = BandState()
    XCTAssertEqual(
      state.update(.screenConfigurationChanged, screens: [screen()], hideNotch: true),
      [.show(displayID: 1, frame: original)])
  }

  func testSpaceChangesEmitNoWindowOperationsEvenWithTransientGeometry() {
    var state = BandState()
    _ = state.update(.screenConfigurationChanged, screens: [screen()], hideNotch: true)
    for screens in [[screen(inset: 0, gap: 0)], [screen(gap: 70)], [], [screen(id: 2)]] {
      // No commands means no create, close, order-out, order-front or resize.
      XCTAssertEqual(state.update(.spaceChanged, screens: screens, hideNotch: true), [])
      XCTAssertEqual(state.frames, [1: original])
    }
  }

  func testSpaceBeforeAnyGoodMeasurementDoesNotCreateOrRememberABand() {
    var state = BandState()
    XCTAssertEqual(state.update(.spaceChanged, screens: [screen()], hideNotch: true), [])
    XCTAssertEqual(state.update(.spaceChanged, screens: [screen(inset: 0)], hideNotch: true), [])
    XCTAssertTrue(state.frames.isEmpty)
    XCTAssertEqual(
      state.update(.screenConfigurationChanged, screens: [screen(inset: 0)], hideNotch: true), [])
    XCTAssertTrue(state.frames.isEmpty)
  }

  func testSettingsKeepTheLastGoodGeometryThroughZeroSmallerAndLargerInsets() {
    var state = BandState()
    _ = state.update(.screenConfigurationChanged, screens: [screen()], hideNotch: true)
    for sample in [screen(inset: 0, gap: 0), screen(gap: 0), screen(inset: 50, gap: 50)] {
      XCTAssertEqual(state.update(.settingsChanged, screens: [sample], hideNotch: true), [])
      XCTAssertEqual(state.frames, [1: original])
    }
  }

  func testSameSizeConfigurationCanGrowAndMoveButNeverShrinkTheBand() {
    var state = BandState()
    _ = state.update(.screenConfigurationChanged, screens: [screen()], hideNotch: true)
    // A hidden menu bar at the same screen size is not a new measure.
    XCTAssertEqual(
      state.update(.screenConfigurationChanged, screens: [screen(gap: 0)], hideNotch: true),
      [.show(displayID: 1, frame: original)])
    let moved = CGRect(x: -1512, y: 200, width: 1512, height: 982)
    let grown = CGRect(x: -1512, y: 1142, width: 1512, height: 40)
    XCTAssertEqual(
      state.update(
        .screenConfigurationChanged, screens: [screen(gap: 40, frame: moved)], hideNotch: true),
      [.show(displayID: 1, frame: grown)])
    XCTAssertEqual(
      state.update(
        .screenConfigurationChanged, screens: [screen(gap: 0, frame: moved)], hideNotch: true),
      [.show(displayID: 1, frame: grown)])
    XCTAssertEqual(state.frames, [1: grown])
  }

  func testZeroInsetAtTheSameSizeNeverClosesTheBand() {
    var state = BandState()
    _ = state.update(.screenConfigurationChanged, screens: [screen()], hideNotch: true)
    XCTAssertEqual(
      state.update(.screenConfigurationChanged, screens: [screen(inset: 0)], hideNotch: true),
      [.show(displayID: 1, frame: original)])
    XCTAssertEqual(state.frames, [1: original])
    XCTAssertEqual(state.update(.settingsChanged, screens: [screen(inset: 0)], hideNotch: true), [])
    XCTAssertEqual(state.update(.spaceChanged, screens: [screen()], hideNotch: true), [])
    XCTAssertEqual(state.frames, [1: original])
  }

  func testWakeInAFullScreenSpaceKeepsTheDesktopBand() {
    // A full-screen Space hides the menu bar, and its app can hide the notch area too.
    for fullScreen in [screen(gap: 0), screen(inset: 0, gap: 0)] {
      var state = BandState()
      _ = state.update(.screenConfigurationChanged, screens: [screen()], hideNotch: true)
      XCTAssertEqual(state.update(.spaceChanged, screens: [fullScreen], hideNotch: true), [])
      // Wake and display wake arrive as configuration events.
      XCTAssertEqual(
        state.update(.screenConfigurationChanged, screens: [fullScreen], hideNotch: true),
        [.show(displayID: 1, frame: original)])
      XCTAssertEqual(state.update(.spaceChanged, screens: [screen()], hideNotch: true), [])
      XCTAssertEqual(state.frames, [1: original])
    }
  }

  func testDifferentScreenSizeTakesTheNewMeasureEvenWhenLowerOrMissing() {
    var state = BandState()
    _ = state.update(.screenConfigurationChanged, screens: [screen()], hideNotch: true)
    let scaled = screen(inset: 27, gap: 28, frame: CGRect(x: 0, y: 0, width: 1800, height: 1169))
    XCTAssertEqual(
      state.update(.screenConfigurationChanged, screens: [scaled], hideNotch: true),
      [.show(displayID: 1, frame: CGRect(x: 0, y: 1141, width: 1800, height: 28))])
    // The area below the camera housing is a shorter screen without a notch.
    let below = screen(inset: 0, gap: 0, frame: CGRect(x: 0, y: 0, width: 1512, height: 950))
    XCTAssertEqual(
      state.update(.screenConfigurationChanged, screens: [below], hideNotch: true),
      [.close(displayID: 1)])
    XCTAssertTrue(state.frames.isEmpty)
  }

  func testDisplayThatLeavesClosesAndReturnsAtItsLastGoodHeight() {
    var state = BandState()
    _ = state.update(.screenConfigurationChanged, screens: [screen()], hideNotch: true)
    XCTAssertEqual(
      state.update(.screenConfigurationChanged, screens: [], hideNotch: true),
      [.close(displayID: 1)])
    XCTAssertTrue(state.frames.isEmpty)
    // The same display returns at the same size while the menu bar is hidden.
    XCTAssertEqual(
      state.update(.screenConfigurationChanged, screens: [screen(gap: 0)], hideNotch: true),
      [.show(displayID: 1, frame: original)])
    XCTAssertEqual(state.frames, [1: original])
  }

  func testUnknownDisplayWithZeroInsetGetsNoBand() {
    var state = BandState()
    for event in [BandState.Event.screenConfigurationChanged, .settingsChanged, .spaceChanged] {
      XCTAssertEqual(state.update(event, screens: [screen(inset: 0)], hideNotch: true), [])
      XCTAssertTrue(state.frames.isEmpty)
    }
  }

  func testDisconnectedDisplayClosesOnlyAtAConfigurationChange() {
    var state = BandState()
    _ = state.update(.screenConfigurationChanged, screens: [screen()], hideNotch: true)
    XCTAssertEqual(state.update(.settingsChanged, screens: [], hideNotch: true), [])
    XCTAssertEqual(state.frames, [1: original])
    XCTAssertEqual(
      state.update(.screenConfigurationChanged, screens: [], hideNotch: true),
      [.close(displayID: 1)])
    XCTAssertTrue(state.frames.isEmpty)
  }

  func testReplacementDisplayDoesNotInheritTheOldIdentityOrHeight() {
    var state = BandState()
    _ = state.update(.screenConfigurationChanged, screens: [screen()], hideNotch: true)
    XCTAssertEqual(
      state.update(
        .screenConfigurationChanged, screens: [screen(id: 2, inset: 0)], hideNotch: true),
      [.close(displayID: 1)])
    XCTAssertTrue(state.frames.isEmpty)
    XCTAssertEqual(
      state.update(.screenConfigurationChanged, screens: [screen(id: 2, gap: 40)], hideNotch: true),
      [.show(displayID: 2, frame: CGRect(x: 0, y: 942, width: 1512, height: 40))])
  }

  func testHideNotchOffClosesAndReenableUsesTheLastConfirmedGeometry() {
    var state = BandState()
    _ = state.update(.screenConfigurationChanged, screens: [screen()], hideNotch: true)
    XCTAssertEqual(
      state.update(.settingsChanged, screens: [screen(inset: 0)], hideNotch: false),
      [.close(displayID: 1)])
    XCTAssertTrue(state.frames.isEmpty)
    XCTAssertEqual(
      state.update(.settingsChanged, screens: [screen(inset: 0)], hideNotch: true),
      [.show(displayID: 1, frame: original)])
  }

  func testConfigurationWhileDisabledReplacesTheCachedHeight() {
    var state = BandState()
    _ = state.update(.screenConfigurationChanged, screens: [screen()], hideNotch: false)
    XCTAssertEqual(
      state.update(.screenConfigurationChanged, screens: [screen(gap: 40)], hideNotch: false), [])
    XCTAssertEqual(
      state.update(.settingsChanged, screens: [screen(inset: 0)], hideNotch: true),
      [.show(displayID: 1, frame: CGRect(x: 0, y: 942, width: 1512, height: 40))])
  }

  func testMeasurementsRemainIndependentForEachDisplay() {
    var state = BandState()
    _ = state.update(
      .screenConfigurationChanged, screens: [screen(), screen(id: 2, gap: 40)], hideNotch: true)
    XCTAssertEqual(
      state.update(.settingsChanged, screens: [screen(id: 2, inset: 0)], hideNotch: true), [])
    XCTAssertEqual(
      state.frames, [1: original, 2: CGRect(x: 0, y: 942, width: 1512, height: 40)])
    XCTAssertEqual(
      state.update(.screenConfigurationChanged, screens: [screen()], hideNotch: true),
      [.close(displayID: 2), .show(displayID: 1, frame: original)])
  }

  /// Applies the commands to a fake window table, as the controller does with the real windows.
  /// Returns false when a command closes a window that does not exist.
  private func apply(_ actions: [BandState.Action], to windows: inout [UInt32: CGRect]) -> Bool {
    for action in actions {
      switch action {
      case .show(let id, let frame):
        windows[id] = frame
      case .close(let id):
        if windows.removeValue(forKey: id) == nil { return false }
      }
    }
    return true
  }

  /// Every sequence of three events over well-formed and malformed screen lists: duplicate
  /// displays, an empty list, zero and not-a-number insets, a menu bar gap of zero. Every sample
  /// has the same screen size, so a listed display never loses height.
  func testEveryShortSequenceKeepsTheWindowsEqualToTheRequestedFrames() {
    let samples: [[BandState.Screen]] = [
      [], [screen()], [screen(inset: 0, gap: 0)], [screen(gap: 0)], [screen(inset: .nan)],
      [screen(id: 2, gap: 40)], [screen(), screen(id: 2, gap: 40)],
      [screen(), screen(inset: 0)],
    ]
    var steps: [(event: BandState.Event, screens: [BandState.Screen], hideNotch: Bool)] = []
    for event in [BandState.Event.screenConfigurationChanged, .settingsChanged, .spaceChanged] {
      for sample in samples {
        for hideNotch in [true, false] {
          steps.append((event: event, screens: sample, hideNotch: hideNotch))
        }
      }
    }
    for first in steps.indices {
      for second in steps.indices {
        for third in steps.indices {
          var state = BandState()
          var windows: [UInt32: CGRect] = [:]
          for index in [first, second, third] {
            let step = steps[index]
            let before = state.frames
            let actions = state.update(
              step.event, screens: step.screens, hideNotch: step.hideNotch)
            let ids = actions.map { action -> UInt32 in
              switch action {
              case .show(let id, _): return id
              case .close(let id): return id
              }
            }
            let closesOnlyExistingWindows = apply(actions, to: &windows)
            let oneCommandPerDisplay = Set(ids).count == ids.count
            let windowsMatchTheState = windows == state.frames
            let spaceDoesNothing =
              step.event != .spaceChanged || (actions.isEmpty && state.frames == before)
            let offMeansNoBand =
              step.event == .spaceChanged || step.hideNotch || state.frames.isEmpty
            // With Hide Notch on, a band leaves only with its display and never loses height.
            var bandsSurvive = true
            if step.event != .spaceChanged && step.hideNotch {
              let listed = Set(step.screens.map(\.id))
              for (id, frame) in before {
                if step.event == .screenConfigurationChanged && !listed.contains(id) {
                  bandsSurvive = bandsSurvive && state.frames[id] == nil
                } else {
                  bandsSurvive = bandsSurvive && (state.frames[id]?.height ?? 0) >= frame.height
                }
              }
            }
            guard
              closesOnlyExistingWindows, oneCommandPerDisplay, windowsMatchTheState,
              spaceDoesNothing, offMeansNoBand, bandsSurvive
            else {
              XCTFail("steps \([first, second, third]) break an invariant at step \(index)")
              return
            }
          }
        }
      }
    }
  }
}
