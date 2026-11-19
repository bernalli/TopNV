import XCTest
@testable import TopNVCore

final class SpaceSwitchMeasurementsTests: XCTestCase {
  private let start = DispatchTime(uptimeNanoseconds: 1_000_000_000)

  func testNotificationForAnotherDisplayDoesNotCompleteTheRequest() throws {
    var measurements = SpaceSwitchMeasurements()
    let request = SpaceSwitchMeasurements.Request(display: "main", origin: 10, target: 20, start: start)
    measurements.record(request)

    let unrelated = start + .milliseconds(10)
    XCTAssertTrue(measurements.observe(display: "other", current: 20, at: unrelated).isEmpty)

    let matched = measurements.observe(display: "main", current: 20, at: start + .milliseconds(15))
    XCTAssertEqual(matched.map(\.identifier), [request.identifier])
    let unmatched = try XCTUnwrap(matched.first?.lastUnmatched)
    XCTAssertEqual(unmatched.received, unrelated)
    XCTAssertNil(unmatched.current)
    XCTAssertNil(measurements.expire(request.identifier))
  }

  func testBurstCompletesOnlyTheRequestWhoseDestinationIsObserved() {
    var measurements = SpaceSwitchMeasurements()
    let first = SpaceSwitchMeasurements.Request(display: "main", origin: 10, target: 20, start: start)
    let second = SpaceSwitchMeasurements.Request(
      display: "main", origin: 20, target: 30, start: start + .milliseconds(1))
    measurements.record(first)
    measurements.record(second)

    let firstNotice = measurements.observe(display: "main", current: 20, at: start + .milliseconds(5))
    XCTAssertEqual(firstNotice.map(\.identifier), [first.identifier])
    let secondNotice = measurements.observe(display: "main", current: 30, at: start + .milliseconds(8))
    XCTAssertEqual(secondNotice.map(\.identifier), [second.identifier])
    XCTAssertNil(measurements.expire(first.identifier))
    XCTAssertNil(measurements.expire(second.identifier))
    XCTAssertTrue(measurements.isEmpty)
  }

  func testTimeoutKeepsTheLastMismatchAndDoesNotExpireOtherRequests() throws {
    var measurements = SpaceSwitchMeasurements()
    let first = SpaceSwitchMeasurements.Request(display: "main", origin: 10, target: 20, start: start)
    let second = SpaceSwitchMeasurements.Request(display: "main", origin: 10, target: 30, start: start)
    measurements.record(first)
    measurements.record(second)

    XCTAssertTrue(measurements.observe(display: "main", current: 10, at: start + .milliseconds(5)).isEmpty)
    let latest = start + .milliseconds(8)
    XCTAssertTrue(measurements.observe(display: "main", current: 99, at: latest).isEmpty)

    let expired = try XCTUnwrap(measurements.expire(first.identifier))
    XCTAssertEqual(expired.identifier, first.identifier)
    XCTAssertEqual(expired.lastUnmatched?.received, latest)
    XCTAssertEqual(expired.lastUnmatched?.current, 99)
    XCTAssertNil(measurements.expire(first.identifier))
    XCTAssertEqual(measurements.expire(second.identifier)?.identifier, second.identifier)
  }

  func testLateNotificationCannotCompleteAnExpiredMeasurement() {
    var measurements = SpaceSwitchMeasurements()
    let request = SpaceSwitchMeasurements.Request(display: "main", origin: 10, target: 20, start: start)
    measurements.record(request)

    XCTAssertTrue(measurements.observe(display: "main", current: 20, at: request.deadline).isEmpty)
    XCTAssertEqual(measurements.expire(request.identifier)?.identifier, request.identifier)
  }

  func testFailedReadDoesNotEraseTheLastReadableMismatch() throws {
    var measurements = SpaceSwitchMeasurements()
    let request = SpaceSwitchMeasurements.Request(display: "main", origin: 10, target: 20, start: start)
    measurements.record(request)

    let mismatch = start + .milliseconds(5)
    XCTAssertTrue(measurements.observe(display: "main", current: 30, at: mismatch).isEmpty)
    XCTAssertTrue(measurements.observe(display: nil, current: nil, at: start + .milliseconds(8)).isEmpty)

    let expired = try XCTUnwrap(measurements.expire(request.identifier))
    XCTAssertEqual(expired.lastUnmatched?.received, mismatch)
    XCTAssertEqual(expired.lastUnmatched?.current, 30)
  }

  func testDrainReturnsOnlyPendingRequestsAndEmptiesTheQueue() {
    var measurements = SpaceSwitchMeasurements()
    let completed = SpaceSwitchMeasurements.Request(display: "main", origin: 10, target: 20, start: start)
    let first = SpaceSwitchMeasurements.Request(display: "main", origin: 20, target: 30, start: start)
    let second = SpaceSwitchMeasurements.Request(display: "main", origin: 20, target: 10, start: start)
    for request in [completed, first, second] { measurements.record(request) }

    let observed = measurements.observe(display: "main", current: 20, at: start + .milliseconds(5))
    XCTAssertEqual(observed.map(\.identifier), [completed.identifier])
    XCTAssertEqual(measurements.drain().map(\.identifier), [first.identifier, second.identifier])
    XCTAssertTrue(measurements.isEmpty)
    XCTAssertNil(measurements.expire(first.identifier))
    XCTAssertTrue(measurements.drain().isEmpty)
  }

  func testCoalescedNotificationCanObserveTwoRequestsForTheSameDestination() {
    var measurements = SpaceSwitchMeasurements()
    let first = SpaceSwitchMeasurements.Request(display: "main", origin: 10, target: 20, start: start)
    let second = SpaceSwitchMeasurements.Request(display: "main", origin: 10, target: 20, start: start)
    measurements.record(first)
    measurements.record(second)

    let matched = measurements.observe(display: "main", current: 20, at: start + .milliseconds(5))
    XCTAssertEqual(matched.map(\.identifier), [first.identifier, second.identifier])
    XCTAssertTrue(measurements.isEmpty)
  }
}
