import AppKit
import XCTest

@testable import TopNVCore

final class OverlayBehaviorTests: XCTestCase {
  func testKeyedOverlayBelongsOnlyToItsSpaceAndNeverFullScreen() {
    XCTAssertEqual(OverlayBehavior.keyed, [.transient, .ignoresCycle])
    XCTAssertFalse(OverlayBehavior.keyed.contains(.canJoinAllSpaces))
    XCTAssertFalse(OverlayBehavior.keyed.contains(.fullScreenAuxiliary))
  }

  func testCornersHideInMissionControl() {
    XCTAssertTrue(OverlayBehavior.corner.contains(.transient))
    XCTAssertFalse(OverlayBehavior.corner.contains(.stationary))
  }

  func testBarHidesInMissionControl() {
    XCTAssertTrue(OverlayBehavior.bar.contains(.transient))
    XCTAssertFalse(OverlayBehavior.bar.contains(.stationary))
  }

  func testEveryOverlayKeepsItsSpacesBehavior() {
    for behavior in [OverlayBehavior.bar, OverlayBehavior.corner] {
      XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
      XCTAssertTrue(behavior.contains(.ignoresCycle))
      XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
    }
  }
}
