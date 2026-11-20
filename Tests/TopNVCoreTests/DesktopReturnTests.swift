import CoreGraphics
import XCTest
@testable import TopNVCore

final class DesktopReturnTests: XCTestCase {
  private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let band = CGRect(x: 0, y: 949, width: 1512, height: 33)
  // Window 20978 before Show Desktop and while parked with 12 pt still on screen.
  private let home = CGRect(x: 264, y: 95, width: 832, height: 769)
  private let parked = CGRect(x: -820, y: 166, width: 832, height: 769)
  private var tracker = DesktopReturn()
  private var entrance = BandEntrance()

  @discardableResult
  private func step(_ bounds: CGRect, surface: Int?, number: CGWindowID = 20978,
                    invalid: Bool = false, sliding: Bool = false, alpha: Double = 1) -> BandEntrance.Action? {
    var windows: [MenuBarEvidence.Window] = [
      .init(owner: .windowServer, layer: 24, bounds: band),
      .init(owner: .application, layer: 0, bounds: bounds, number: number)
    ]
    if let surface {
      windows.append(.init(owner: .desktop, layer: surface, bounds: frame, isWindowManager: true,
                           alpha: alpha, number: 21046))
    }
    if sliding {
      windows.append(.init(owner: .desktop, layer: -1, bounds: frame.offsetBy(dx: 200, dy: 0), isWindowManager: true))
    }
    let list = invalid ? nil : windows
    let raw = MenuBarEvidence.evaluate(frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 33),
                                       bandFrame: band, windows: list)
    let result = tracker.resolve(raw, on: frame, windows: list)
    return entrance.update(.sample, enabled: true, samples: [1: .init(result)], reduceMotion: false)[1]
  }

  func testReturningParkedWindowStartsBeforeShowDesktopSurfaceLeaves() {
    XCTAssertNil(step(home, surface: nil))
    XCTAssertEqual(step(parked, surface: 18), .restore)
    XCTAssertEqual(step(parked, surface: 18), .restore)
    XCTAssertEqual(step(parked.offsetBy(dx: 30, dy: 0), surface: 18), .start)
    XCTAssertNil(step(home, surface: 18))
    XCTAssertNil(step(home, surface: nil))
  }

  func testMissionControlRestoresTheKnownThumbnailToItsDesktopFrame() {
    let thumbnail = CGRect(x: 300, y: 250, width: 430, height: 397)
    _ = step(home, surface: nil)
    XCTAssertEqual(step(thumbnail, surface: 19), .restore)
    XCTAssertEqual(step(thumbnail.offsetBy(dx: 12, dy: 0), surface: 19), .restore)
    XCTAssertEqual(step(home, surface: 19), .start)
    XCTAssertNil(step(home, surface: nil))
  }

  func testGrowingThumbnailStartsBeforeReachingHomeAndCanReverse() {
    let small = home.insetBy(dx: 160, dy: 140)
    let growing = home.insetBy(dx: 145, dy: 125)
    _ = step(home, surface: nil)
    XCTAssertEqual(step(small, surface: 19), .restore)
    XCTAssertEqual(step(small.offsetBy(dx: 4, dy: 0), surface: 19), .restore)
    XCTAssertEqual(step(growing, surface: 19), .start)
    XCTAssertNil(step(growing, surface: 19))
    XCTAssertEqual(step(small, surface: 19), .restore)
    XCTAssertEqual(step(growing, surface: 19), .start)
    XCTAssertNil(step(home, surface: nil))
  }

  func testFadingOverviewCanSignalReturnWithUntransformedDocuments() {
    _ = step(home, surface: nil)
    XCTAssertEqual(step(home, surface: 19, alpha: 0.6), .restore)
    XCTAssertEqual(step(home, surface: 19), .restore)
    XCTAssertEqual(step(home, surface: 19, alpha: 0.8), .start)
    XCTAssertNil(step(home, surface: 19, alpha: 0.5))
    XCTAssertEqual(step(home, surface: 19), .restore)
    XCTAssertEqual(step(home, surface: nil), .start)
  }

  func testSingleMissingSurfaceWhileTheDocumentIsStillParkedDoesNotReplay() {
    _ = step(home, surface: nil)
    _ = step(parked, surface: 18)
    XCTAssertEqual(step(parked, surface: nil), .restore)
    XCTAssertEqual(step(parked, surface: 18), .restore)
    XCTAssertEqual(step(home, surface: nil), .start)
    XCTAssertNil(step(home, surface: nil))
  }

  func testFreshWindowOrUnobservedDepartureCannotStartAnEarlyReturn() {
    XCTAssertNil(step(home, surface: nil))
    XCTAssertEqual(step(home, surface: 18), .restore)
    XCTAssertEqual(step(parked, surface: 18), .restore)
    XCTAssertEqual(step(home, surface: 18, number: 555), .restore)
    XCTAssertEqual(step(home, surface: nil), .start)
    XCTAssertNil(step(home, surface: nil))
  }

  func testReversedReturnAndInterruptedEvidence() {
    _ = step(home, surface: nil)
    _ = step(parked, surface: 18)
    XCTAssertEqual(step(home, surface: 18), .start)
    XCTAssertEqual(step(parked, surface: 18), .restore)
    XCTAssertEqual(step(parked, surface: 18, invalid: true), .restore)
    XCTAssertEqual(step(home, surface: 18), .restore)
    XCTAssertNil(step(home, surface: nil))
    _ = step(parked, surface: 18)
    XCTAssertEqual(step(home, surface: 18, sliding: true), .restore)
    XCTAssertNil(step(home, surface: nil))
  }
}

extension DesktopReturnTests {
  func testDockOverviewReturnsOnceAndOrdinaryDockDoesNotArmAnEntrance() {
    func row(_ owner: String, layer: Int, height: Int) -> [String: Any] {
      [kCGWindowOwnerPID as String: 100, kCGWindowOwnerName as String: owner,
       kCGWindowLayer as String: layer, kCGWindowAlpha as String: 1,
       kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 1512, "Height": height]]
    }
    let dock = row("Dock", layer: 20, height: 982)
    let menu = row("Window Server", layer: 24, height: 33)
    let overview = row("Dock", layer: 18, height: 982)
    func sample(_ rows: [[String: Any]]) -> BandEntrance.Action? {
      let list = MenuBarEvidence.windows(from: rows, ownPID: 42, primaryScreenHeight: frame.height)
      let raw = MenuBarEvidence.evaluate(frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 33),
                                         bandFrame: band, windows: list)
      let result = tracker.resolve(raw, on: frame, windows: list)
      return entrance.update(.sample, enabled: true, samples: [1: .init(result)], reduceMotion: false)[1]
    }
    XCTAssertNil(sample([menu, dock]))
    XCTAssertNil(sample([menu, dock, overview])) // App Exposé
    XCTAssertEqual(sample([dock, dock, overview]), .restore)
    XCTAssertEqual(sample([menu, dock]), .start)
    XCTAssertNil(sample([menu, dock]))
  }
}
