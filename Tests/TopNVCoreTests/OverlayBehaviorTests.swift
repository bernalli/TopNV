import AppKit
import XCTest

@testable import TopNVCore

final class OverlayBehaviorTests: XCTestCase {
  func testCornersHideInMissionControl() {
    XCTAssertTrue(OverlayBehavior.corner.contains(.transient))
    XCTAssertFalse(OverlayBehavior.corner.contains(.stationary))
  }

  func testBarStaysInPlaceInMissionControl() {
    XCTAssertTrue(OverlayBehavior.bar.contains(.stationary))
    XCTAssertFalse(OverlayBehavior.bar.contains(.transient))
  }

  func testEveryOverlayKeepsItsSpacesBehavior() {
    for behavior in [OverlayBehavior.bar, OverlayBehavior.corner] {
      XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
      XCTAssertTrue(behavior.contains(.ignoresCycle))
      XCTAssertTrue(behavior.contains(.fullScreenAuxiliary))
    }
  }
}
