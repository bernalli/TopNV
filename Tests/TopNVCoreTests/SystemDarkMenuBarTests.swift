import XCTest
@testable import TopNVCore

final class SystemDarkMenuBarTests: XCTestCase {
  private let testID = "io.github.bernalli.topnv.try125"

  func testOnlyIdentifiableTestCopiesCanRecoverOrEnable() throws {
    for identifier in [nil, "", "io.github.bernalli.topnv", "IO.GITHUB.BERNALLI.TOPNV"] {
      XCTAssertNil(SystemDarkMenuBarState(bundleIdentifier: identifier, saved: true))
    }
    var state = try makeState()
    XCTAssertEqual(state.start(), [])
    let row = state.menuRow(clientAvailable: false)
    XCTAssertEqual(row.kind, .toggle(.systemDarkMenuBar, isOn: false, enabled: false))
  }

  func testLaunchRestoresAnInterruptedRequestWithoutResumingTheProbe() throws {
    var state = try makeState(saved: true)
    let restore = try request(from: state.start(), enabled: false)
    XCTAssertTrue(state.suspendsKey)
    XCTAssertEqual(state.complete(restore, reply: .applied), [.clearMarker])
    XCTAssertFalse(state.suspendsKey)

    var disabled = try makeState(saved: false)
    XCTAssertEqual(disabled.start(), [])
  }

  func testMalformedMarkersOnlyAllowCleanup() throws {
    for malformed: Any in ["false", NSNumber(value: 0), NSNumber(value: 2), [], ["enabled": true]] {
      var state = try makeState(saved: malformed)
      _ = try request(from: state.start(), enabled: false)
    }
  }

  func testKeyIsSuspendedThroughAcknowledgedRestoration() throws {
    var state = try makeState()
    let enable = try request(from: state.toggle(), enabled: true)
    XCTAssertTrue(state.suspendsKey)
    XCTAssertEqual(state.toggle(), [])
    XCTAssertEqual(state.complete(enable, reply: .applied), [])
    let restore = try request(from: state.toggle(), enabled: false)
    XCTAssertTrue(state.suspendsKey)
    XCTAssertEqual(state.toggle(), [])
    XCTAssertEqual(state.complete(restore, reply: .applied), [.clearMarker])
    XCTAssertFalse(state.suspendsKey)
  }

  func testQuitWaitsForEnableThenRestores() throws {
    var state = try makeState()
    let enable = try request(from: state.toggle(), enabled: true)
    XCTAssertEqual(state.quit(), [])
    let restore = try request(from: state.complete(enable, reply: .applied), enabled: false)
    XCTAssertEqual(state.complete(restore, reply: .applied), [.clearMarker, .finishQuit(true)])
  }

  func testQuitWithFailedRestoreIsCancelledAndCanBeRetried() throws {
    var state = try makeState(saved: true)
    let restore = try request(from: state.quit(), enabled: false)
    XCTAssertEqual(state.complete(restore, reply: .uncertain), [.finishQuit(false)])
    XCTAssertTrue(state.needsRestore)
    let retry = try request(from: state.quit(), enabled: false)
    XCTAssertEqual(state.complete(retry, reply: .applied), [.clearMarker, .finishQuit(true)])
  }

  func testLateRestoreReplyAfterQuitTimeoutStillClearsTheMarker() throws {
    var state = try makeState(saved: true)
    let restore = try request(from: state.quit(), enabled: false)
    XCTAssertEqual(state.timeout(restore), [.finishQuit(false)])
    XCTAssertTrue(state.needsRestore)
    XCTAssertEqual(state.complete(restore, reply: .applied), [.clearMarker])
    XCTAssertFalse(state.needsRestore)
  }

  func testEnableTimeoutSendsDefensiveRestoreAndRequiresRestoreAfterLateEnable() throws {
    var state = try makeState()
    let enable = try request(from: state.toggle(), enabled: true)
    XCTAssertEqual(state.quit(), [])
    let timedOut = state.timeout(enable)
    let defensive = try request(from: timedOut, enabled: false)
    XCTAssertEqual(timedOut, [.send(defensive), .finishQuit(false)])
    XCTAssertEqual(state.complete(defensive, reply: .applied), [])
    XCTAssertTrue(state.needsRestore)
    XCTAssertEqual(state.quit(), [.finishQuit(false)])

    let restore = try request(from: state.complete(enable, reply: .applied), enabled: false)
    XCTAssertNotEqual(restore, defensive)
    XCTAssertEqual(state.quit(), [])
    XCTAssertEqual(state.complete(restore, reply: .applied), [.clearMarker, .finishQuit(true)])
  }

  func testLateDefensiveRestoreCannotUndoTheNextEnable() throws {
    var state = try makeState()
    let enable = try request(from: state.toggle(), enabled: true)
    let defensive = try request(from: state.timeout(enable), enabled: false)
    let restore = try request(from: state.complete(enable, reply: .applied), enabled: false)
    XCTAssertEqual(state.complete(restore, reply: .applied), [.clearMarker])
    XCTAssertFalse(state.suspendsKey)
    XCTAssertEqual(state.toggle(), [])
    XCTAssertEqual(state.complete(defensive, reply: .applied), [])
    _ = try request(from: state.toggle(), enabled: true)
  }

  func testUncertainEnableAndFailedCleanupReturnTheKeyAndRetainTheMarker() throws {
    var state = try makeState()
    let enable = try request(from: state.toggle(), enabled: true)
    let effects = state.complete(enable, reply: .uncertain)
    let defensive = try request(from: effects, enabled: false)
    XCTAssertEqual(effects, [.send(defensive)])
    XCTAssertEqual(state.complete(defensive, reply: .uncertain), [])
    XCTAssertFalse(state.suspendsKey)
    XCTAssertTrue(state.needsRestore)
    let retry = try request(from: state.quit(), enabled: false)
    XCTAssertEqual(state.complete(retry, reply: .uncertain), [.finishQuit(false)])
  }

  func testUnsentEnableCanQuitWithoutRestoring() throws {
    var state = try makeState()
    let enable = try request(from: state.toggle(), enabled: true)
    XCTAssertEqual(state.quit(), [])
    XCTAssertEqual(state.complete(enable, reply: .notSent), [.clearMarker, .finishQuit(true)])
    XCTAssertFalse(state.needsRestore)
    XCTAssertFalse(state.suspendsKey)
  }

  private func makeState(saved: Any? = nil) throws -> SystemDarkMenuBarState {
    try XCTUnwrap(SystemDarkMenuBarState(bundleIdentifier: testID, saved: saved))
  }

  private func request(
    from effects: [SystemDarkMenuBarState.Effect], enabled: Bool
  ) throws -> SystemDarkMenuBarState.Request {
    let requests = effects.compactMap { effect -> SystemDarkMenuBarState.Request? in
      guard case .send(let request) = effect else { return nil }
      return request
    }
    XCTAssertEqual(requests.count, 1)
    let request = try XCTUnwrap(requests.first)
    XCTAssertEqual(request.enabled, enabled)
    return request
  }
}
