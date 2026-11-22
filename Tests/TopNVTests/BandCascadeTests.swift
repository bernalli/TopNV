import AppKit
import XCTest
@testable import TopNV
@testable import TopNVCore

@MainActor
final class BandCascadeTests: XCTestCase {
  func testReturnUsesPreparedStationaryWindowsAndHandsBackToBand() throws {
    _ = NSApplication.shared
    let executor = BandExecutor()
    defer { executor.closeAll() }
    let steady = ExecutorPlans.display()
    let id = BarRegistryID(display: 1, part: .band)
    let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
    let window = try ExecutorPlans.window(executor.apply(.init(displays: [1: steady]))[id])
    let created = NSApp.windows.filter { !existing.contains(ObjectIdentifier($0)) }
    let strips = created.compactMap { $0 as? BandSliceWindow }.sorted { $0.frame.minX < $1.frame.minX }
    XCTAssertEqual(strips.count, 64)
    let frames = strips.map(\.frame)
    XCTAssertTrue(strips.allSatisfy {
      $0.alphaValue == 0 && $0.collectionBehavior.contains(.stationary) && $0.level == window.level
    })
    XCTAssertEqual(frames.first?.minX, window.frame.minX)
    XCTAssertEqual(frames.last?.maxX, window.frame.maxX)
    for (left, right) in zip(frames, frames.dropFirst()) { XCTAssertEqual(left.maxX, right.minX) }
    var previous = strips.map(\.alphaValue)
    for width in [40.0, 121.5, 200.0] {
      var returning = ExecutorPlans.display(band: ExecutorPlans.part(mask: .rect(
        CGRect(x: (200 - width) / 2, y: 0, width: width, height: 34))))
      returning.cascadesOnReturn = true
      executor.apply(.init(displays: [1: returning]))
      let alpha = strips.map(\.alphaValue)
      XCTAssertEqual(alpha, Array(alpha.reversed()))
      XCTAssertTrue(zip(previous, alpha).allSatisfy { $0 <= $1 })
      XCTAssertEqual(strips.map(\.frame), frames)
      XCTAssertEqual(window.alphaValue, 0)
      previous = alpha
    }
    XCTAssertTrue(previous.allSatisfy { $0 == 1 })
    executor.apply(.init(displays: [1: steady]))
    XCTAssertTrue(strips.allSatisfy { $0.alphaValue == 0 })
    XCTAssertEqual(window.alphaValue, 1)
    executor.apply(.init(displays: [:]))
    XCTAssertTrue(strips.allSatisfy { !$0.isVisible })
  }

  func testInterruptedReturnRestoresTheBandForAnAbsentDisplayAndHidesItInOverview() throws {
    _ = NSApplication.shared
    let executor = BandExecutor()
    defer { executor.closeAll() }
    let id = BarRegistryID(display: 1, part: .band)
    let steady = ExecutorPlans.display()
    let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
    let window = try ExecutorPlans.window(executor.apply(.init(displays: [1: steady]))[id])
    let strips = NSApp.windows.filter { !existing.contains(ObjectIdentifier($0)) }
      .compactMap { $0 as? BandSliceWindow }
    var returning = ExecutorPlans.display(band: ExecutorPlans.part(mask: .rect(
      CGRect(x: 60, y: 0, width: 80, height: 34))))
    returning.cascadesOnReturn = true
    let absent = ExecutorPlans.display(band: ExecutorPlans.part(alpha: .hold), geometry: nil)
    let overview = ExecutorPlans.display(band: ExecutorPlans.part(alpha: .value(0)), kind: .overview)
    let interruptions: [(BarDisplayPlan, CGFloat)] = [(absent, 1), (overview, 0)]

    for (interrupted, expectedAlpha) in interruptions {
      executor.apply(.init(displays: [1: returning]))
      XCTAssertEqual(window.alphaValue, 0)
      XCTAssertTrue(strips.contains { $0.alphaValue > 0 })
      executor.apply(.init(displays: [1: interrupted]))
      XCTAssertEqual(window.alphaValue, expectedAlpha)
      XCTAssertTrue(strips.allSatisfy { $0.alphaValue == 0 })
      executor.apply(.init(displays: [1: steady]))
      XCTAssertEqual(window.alphaValue, 1)
    }
  }

  func testBandAlphaWhenAReturnIsInterrupted() {
    XCTAssertEqual(BandExecutor.presentationAlpha(.value(1), returning: true, wasReturning: false), .value(0))
    XCTAssertEqual(BandExecutor.presentationAlpha(.hold, returning: false, wasReturning: true), .value(1))
    XCTAssertEqual(BandExecutor.presentationAlpha(.value(0), returning: false, wasReturning: true), .value(0))
    XCTAssertEqual(BandExecutor.presentationAlpha(.hold, returning: false, wasReturning: false), .hold)
  }
}
