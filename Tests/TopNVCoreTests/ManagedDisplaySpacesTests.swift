import XCTest
@testable import TopNVCore

final class ManagedDisplaySpacesTests: XCTestCase {
  private let desktops: [[String: Any]] = [
    ["ManagedSpaceID": 90, "type": 0], ["id64": 3, "type": 4], ["ManagedSpaceID": 27, "type": 0]
  ]

  private func display(_ current: Any, _ spaces: [[String: Any]], name: String = "Main") -> [String: Any] {
    ["Display Identifier": name, "Current Space": ["ManagedSpaceID": current], "Spaces": spaces]
  }

  func testUsesMainUUIDAndListOrderIncludingFullScreen() throws {
    let displays = [display(90, desktops, name: "other"), display(3, desktops, name: "abCD")]
    let state = try ManagedDisplaySpaces(displays, mainUUID: "ABCD")
    XCTAssertEqual(state.identifier, "abCD")
    XCTAssertEqual(state.currentID, 3)
    XCTAssertEqual(try state.neighbor(.left), 90)
    XCTAssertEqual(try state.neighbor(.right), 27)
  }

  func testStopsAtEitherEdgeOfMainDisplay() throws {
    let first = try ManagedDisplaySpaces([display(90, desktops)], mainUUID: "ABCD")
    let last = try ManagedDisplaySpaces([display(27, desktops)], mainUUID: "ABCD")
    XCTAssertNil(try first.neighbor(.left))
    XCTAssertNil(try last.neighbor(.right))
    XCTAssertEqual(try first.neighbor(.right), 3)
  }

  func testRejectsAmbiguousOrMissingMainDisplay() {
    let other = display(90, desktops, name: "other")
    XCTAssertThrowsError(try ManagedDisplaySpaces([other], mainUUID: "ABCD"))
    let ambiguous = [display(90, desktops), display(27, desktops, name: "ABCD")]
    XCTAssertThrowsError(try ManagedDisplaySpaces(ambiguous, mainUUID: "ABCD"))
  }

  func testRejectsUnreadableAndDuplicateIDsAnywhereInList() {
    for bad in [["type": 0], ["id64": 3, "type": 0], ["id64": -1, "type": 0],
                ["id64": 0, "type": 0], ["id64": true, "type": 0], ["id64": 1.5, "type": 0],
                ["id64": "2", "type": 0], ["id64": 55]] as [[String: Any]] {
      XCTAssertThrowsError(try ManagedDisplaySpaces([display(90, desktops + [bad])], mainUUID: "ABCD"))
    }
    XCTAssertThrowsError(try ManagedDisplaySpaces([display(1, desktops)], mainUUID: "ABCD"))
    XCTAssertThrowsError(try ManagedDisplaySpaces([display(NSNull(), desktops)], mainUUID: "ABCD"))
  }

  func testUnknownTypeIsNeverEnteredExitedOrSkipped() throws {
    let spaces = desktops + [["ManagedSpaceID": 99, "type": 8]] + [["ManagedSpaceID": 42, "type": 0]]
    let before = try ManagedDisplaySpaces([display(27, spaces)], mainUUID: "ABCD")
    let unknown = try ManagedDisplaySpaces([display(99, spaces)], mainUUID: "ABCD")
    XCTAssertEqual(try before.neighbor(.left), 3)
    XCTAssertThrowsError(try before.neighbor(.right))
    XCTAssertThrowsError(try unknown.neighbor(.left))
    XCTAssertThrowsError(try unknown.neighbor(.right))
  }
}
