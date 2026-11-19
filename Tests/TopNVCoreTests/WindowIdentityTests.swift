import CoreGraphics
import XCTest
@testable import TopNVCore

/// Window numbers and the Dock identity read from the window list, and the Dock overview rule.
final class WindowIdentityTests: XCTestCase {
  private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let band = CGRect(x: 0, y: 949, width: 1512, height: 33)

  private func row(_ owner: String?, pid: Int = 100, layer: Int, height: Int = 982, originX: Int = 0,
                   alpha: Double = 1, number: Any? = nil) -> [String: Any] {
    var result: [String: Any] = [
      kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha,
      kCGWindowBounds as String: ["X": originX, "Y": 0, "Width": 1512, "Height": height]
    ]
    result[kCGWindowOwnerName as String] = owner
    result[kCGWindowNumber as String] = number
    return result
  }

  private func parse(_ rows: [[String: Any]], dockPID: Int32? = nil) -> [MenuBarEvidence.Window]? {
    MenuBarEvidence.windows(from: rows, ownPID: 42, primaryScreenHeight: frame.height, dockPID: dockPID)
  }

  private func surfaceLayer(_ rows: [[String: Any]], dockPID: Int32? = nil) -> Int? {
    MenuBarEvidence.evaluate(frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 33), bandFrame: band,
                             windows: parse(rows, dockPID: dockPID)).revealLayer
  }

  func testAnUnusableWindowNumberLeavesTheWindowWithoutIdentityAndTheListValid() throws {
    XCTAssertEqual(try XCTUnwrap(parse([row("Notes", layer: 0, number: 77)])).first?.number, 77)
    XCTAssertEqual(try XCTUnwrap(parse([row("Notes", layer: 0, number: UInt32.max)])).first?.number, .max)
    let unusable: [Any?] = [nil, "77", -1, 1.5, 4_294_967_296, Double.nan, Double.infinity, true, [77], NSNull()]
    for number in unusable {
      let windows = try XCTUnwrap(parse([row("Notes", layer: 0, number: number)]), "\(String(describing: number))")
      XCTAssertEqual(windows.count, 1)
      XCTAssertNil(windows[0].number, "\(String(describing: number))")
      XCTAssertEqual(windows[0].owner, .application)
    }
  }

  func testTheDockIsKnownByItsProcessWhateverItsNameAndNeverByOurOwn() throws {
    let overview = [row("Window Server", layer: 24, height: 33), row("Banchina", pid: 7, layer: 18),
                    row("Banchina", pid: 7, layer: 20), row("Banchina", pid: 7, layer: 20)]
    XCTAssertEqual(surfaceLayer(overview, dockPID: 7), 18)
    XCTAssertNil(surfaceLayer(overview))
    XCTAssertNil(surfaceLayer(overview, dockPID: 8))
    XCTAssertEqual(try XCTUnwrap(parse(overview)).filter { $0.owner == .desktop }.count, 0)
    // Our own windows never count as the Dock, by name or by a wrong process number.
    let own = [row("Dock", pid: 42, layer: 18), row("Dock", pid: 42, layer: 20), row("Dock", pid: 42, layer: 20)]
    XCTAssertNil(surfaceLayer(own))
    XCTAssertNil(surfaceLayer(own, dockPID: 42))
    XCTAssertEqual(try XCTUnwrap(parse(own, dockPID: 42)).map(\.owner), [.ownApp, .ownApp, .ownApp])
  }

  func testTheDockOverviewNeedsItsOwnSurfacesOnThisDisplay() {
    let menu = row("Window Server", layer: 24, height: 33)
    let overview = row("Dock", layer: 18)
    let dock = row("Dock", layer: 20)
    XCTAssertEqual(surfaceLayer([menu, overview, dock, dock]), 18)
    let notAnOverview: [[[String: Any]]] = [
      [menu, dock, dock],
      [menu, overview],
      [menu, overview, dock],
      [menu, overview, overview, dock, dock],
      [menu, overview, dock, row("Dock", layer: 20, alpha: 0)],
      [menu, overview, dock, row("Dock", layer: 20, originX: 1512)],
      [menu, overview, dock, row("Finder", layer: 20)],
      [menu, row("Dock", layer: 18, alpha: 0), dock, dock],
      [menu, row("Dock", layer: 18, height: 900), dock, dock],
      [menu, row("Dock", layer: 19), dock, dock],
      [menu, row("Notes", layer: 18), dock, dock]
    ]
    for (index, rows) in notAnOverview.enumerated() {
      XCTAssertNil(surfaceLayer(rows), "case \(index)")
    }
  }

  func testAWindowManagerSurfaceWinsOverTheDockRule() {
    let rows = [row("Window Server", layer: 24, height: 33), row("Dock", layer: 18), row("Dock", layer: 20),
                row("Dock", layer: 20), row("WindowManager", layer: 19)]
    XCTAssertEqual(surfaceLayer(rows), 19)
  }
}
