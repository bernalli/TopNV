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

  func testRealConfigurationCanShrinkGrowAndMoveTheExistingBand() {
    var state = BandState()
    _ = state.update(.screenConfigurationChanged, screens: [screen()], hideNotch: true)
    XCTAssertEqual(
      state.update(.screenConfigurationChanged, screens: [screen(gap: 0)], hideNotch: true),
      [.show(displayID: 1, frame: CGRect(x: 0, y: 950, width: 1512, height: 32))])
    XCTAssertEqual(
      state.update(
        .screenConfigurationChanged,
        screens: [screen(gap: 40, frame: CGRect(x: -1512, y: 200, width: 1512, height: 982))],
        hideNotch: true),
      [.show(displayID: 1, frame: CGRect(x: -1512, y: 1142, width: 1512, height: 40))])
  }

  func testConfirmedZeroInsetClosesTheBandAndDiscardsTheOldMeasurement() {
    var state = BandState()
    _ = state.update(.screenConfigurationChanged, screens: [screen()], hideNotch: true)
    XCTAssertEqual(
      state.update(.screenConfigurationChanged, screens: [screen(inset: 0)], hideNotch: true),
      [.close(displayID: 1)])
    XCTAssertTrue(state.frames.isEmpty)
    XCTAssertEqual(state.update(.settingsChanged, screens: [screen(inset: 0)], hideNotch: true), [])
    XCTAssertEqual(state.update(.spaceChanged, screens: [screen()], hideNotch: true), [])
    XCTAssertTrue(state.frames.isEmpty)
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
}
