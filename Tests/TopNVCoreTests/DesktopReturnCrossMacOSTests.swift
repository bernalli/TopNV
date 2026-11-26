import CoreGraphics
import XCTest
@testable import TopNVCore

final class DesktopReturnCrossMacOSTests: XCTestCase {
  private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let band = CGRect(x: 0, y: 949, width: 1512, height: 33)
  private let home = CGRect(x: 264, y: 95, width: 832, height: 769)
  private let parked = CGRect(x: -820, y: 166, width: 832, height: 769)
  private var tracker = DesktopReturn()
  private var entrance = BandEntrance()

  private func dockRows(doc: CGRect? = nil, alpha: Double = 1, listedBand: CGRect? = nil,
                        bandAlpha: Double = 0, overview: Bool = true) -> [MenuBarEvidence.Window] {
    var windows: [MenuBarEvidence.Window] = [
      .init(owner: .windowServer, layer: 24, bounds: band),
      .init(owner: .application, layer: 0, bounds: doc ?? home, number: 20978),
      .init(owner: .desktop, layer: 20, bounds: frame, number: 9001, isDock: true)
    ]
    if overview {
      windows.append(.init(owner: .desktop, layer: 20, bounds: frame, number: 9002, isDock: true))
      windows.append(.init(owner: .desktop, layer: 18, bounds: frame, alpha: alpha, number: 9003, isDock: true))
    }
    if let listedBand {
      windows.append(.init(owner: .ownApp, layer: -2147483622, bounds: listedBand, alpha: bandAlpha, number: 55677))
    }
    return windows
  }

  @discardableResult
  private func deliver(_ windows: [MenuBarEvidence.Window]) -> BandEntrance.Action? {
    let raw = MenuBarEvidence.evaluate(frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 33),
                                       bandFrame: band, windows: windows)
    let result = tracker.resolve(raw, on: frame, windows: windows, band: (55677, band))
    return entrance.update(.sample, enabled: true, samples: [1: .init(result)], reduceMotion: false)[1]
  }

  func testDockOverviewBandRelistingStartsBeforeOpaqueDockEnds() {
    deliver(dockRows(listedBand: band, bandAlpha: 1, overview: false))
    // Band already removed by Mission Control on the first overview sample.
    XCTAssertEqual(deliver(dockRows()), .restore)
    XCTAssertEqual(deliver(dockRows()), .restore)
    XCTAssertEqual(deliver(dockRows(listedBand: band)), .restore)
    XCTAssertEqual(deliver(dockRows(listedBand: band)), .start)
    XCTAssertNil(deliver(dockRows(listedBand: band, overview: false)))
  }

  func testDockOverviewFadingAlphaStartsBeforeDockLeaves() {
    deliver(dockRows(overview: false))
    XCTAssertEqual(deliver(dockRows(alpha: 1.0)), .restore)
    XCTAssertEqual(deliver(dockRows(alpha: 0.8)), .start)
    XCTAssertEqual(deliver(dockRows(alpha: 1.0)), .restore)
    XCTAssertEqual(deliver(dockRows(overview: false)), .start)
  }

  func testDockHostedShowDesktopParkedDocumentStartsEarly() {
    deliver(dockRows(doc: home, overview: false))
    XCTAssertEqual(deliver(dockRows(doc: parked)), .restore)
    XCTAssertEqual(deliver(dockRows(doc: parked.offsetBy(dx: 24, dy: 0))), .start)
    XCTAssertNil(deliver(dockRows(doc: home, overview: false)))
  }

  func testBandAbsentFromFirstOverviewSampleStillRelistsWhenSeenOnDesktop() {
    func wmRows(surface: Int?, alpha: Double = 1, listedBand: CGRect? = nil,
                bandAlpha: Double = 0) -> [MenuBarEvidence.Window] {
      var windows: [MenuBarEvidence.Window] = [
        .init(owner: .windowServer, layer: 24, bounds: band),
        .init(owner: .application, layer: 0, bounds: home, number: 20978)
      ]
      if let listedBand {
        windows.append(.init(owner: .ownApp, layer: -2147483622, bounds: listedBand, alpha: bandAlpha, number: 55677))
      }
      if let surface {
        windows.append(.init(owner: .desktop, layer: surface, bounds: frame, isWindowManager: true,
                             alpha: alpha, number: 21046))
      }
      return windows
    }
    deliver(wmRows(surface: nil, listedBand: band, bandAlpha: 1))
    XCTAssertEqual(deliver(wmRows(surface: 19)), .restore)
    XCTAssertEqual(deliver(wmRows(surface: 19)), .restore)
    XCTAssertEqual(deliver(wmRows(surface: 19, listedBand: band)), .restore)
    XCTAssertEqual(deliver(wmRows(surface: 19, listedBand: band)), .start)
    // A rebound cancels and must not re-arm from persistent listing.
    XCTAssertNil(deliver(wmRows(surface: 19, alpha: 0.8, listedBand: band)))
    XCTAssertEqual(deliver(wmRows(surface: 19, alpha: 1.0, listedBand: band)), .restore)
    XCTAssertEqual(deliver(wmRows(surface: 19, alpha: 1.0, listedBand: band)), .restore)
    XCTAssertEqual(deliver(wmRows(surface: nil, listedBand: band, bandAlpha: 1)), .start)
  }

  func testShowDesktopWiderSliverAndSubpixelSizeStillStartsEarly() {
    func wmRows(doc: CGRect, surface: Int?) -> [MenuBarEvidence.Window] {
      var windows: [MenuBarEvidence.Window] = [
        .init(owner: .windowServer, layer: 24, bounds: band),
        .init(owner: .application, layer: 0, bounds: doc, number: 20978)
      ]
      if let surface {
        windows.append(.init(owner: .desktop, layer: surface, bounds: frame, isWindowManager: true,
                             alpha: 1, number: 21046))
      }
      return windows
    }
    // 28 pt sliver on screen (wider than the 16 pt interior inset) and 0.5 pt rounding.
    let wideSliver = CGRect(x: -804, y: 166, width: 832.5, height: 769)
    deliver(wmRows(doc: home, surface: nil))
    XCTAssertEqual(deliver(wmRows(doc: wideSliver, surface: 18)), .restore)
    // Sliding along the edge (delta <= 2 pt) stays revealed and keeps the parked anchor.
    XCTAssertEqual(deliver(wmRows(doc: wideSliver.offsetBy(dx: 0, dy: 10), surface: 18)), .restore)
    // Moving 10 pt back toward home starts immediately even while the center is still off-screen.
    XCTAssertEqual(deliver(wmRows(doc: wideSliver.offsetBy(dx: 10, dy: 0), surface: 18)), .start)
    // Reversing back to the parked sliver hides again.
    XCTAssertEqual(deliver(wmRows(doc: wideSliver, surface: 18)), .restore)
    XCTAssertEqual(deliver(wmRows(doc: home, surface: nil)), .start)
  }

  func testParkedSliverJitterTowardHomeStillHoldsOnFadeAndMissedSurface() {
    func wmRows(doc: CGRect, surface: Int?, alpha: Double = 1) -> [MenuBarEvidence.Window] {
      var windows: [MenuBarEvidence.Window] = [
        .init(owner: .windowServer, layer: 24, bounds: band),
        .init(owner: .application, layer: 0, bounds: doc, number: 20978)
      ]
      if let surface {
        windows.append(.init(owner: .desktop, layer: surface, bounds: frame, isWindowManager: true,
                             alpha: alpha, number: 21046))
      }
      return windows
    }
    let wideSliver = CGRect(x: -804, y: 166, width: 832.5, height: 769)
    // Moves 0.62 pt closer to home along the edge (< 2 pt tolerance): still parked.
    let edgeJitter = wideSliver.offsetBy(dx: 0, dy: -10)
    deliver(wmRows(doc: home, surface: nil))
    XCTAssertEqual(deliver(wmRows(doc: wideSliver, surface: 18, alpha: 0.60)), .restore)
    XCTAssertEqual(deliver(wmRows(doc: edgeJitter, surface: 18, alpha: 0.58)), .restore)
    XCTAssertEqual(deliver(wmRows(doc: edgeJitter, surface: nil)), .restore)
    XCTAssertEqual(deliver(wmRows(doc: edgeJitter, surface: 18, alpha: 0.55)), .restore)
    XCTAssertEqual(deliver(wmRows(doc: wideSliver.offsetBy(dx: 12, dy: 0), surface: 18, alpha: 0.55)), .start)
  }

  func testDockParkedDocumentBlocksPrematureBandRelistingAndFade() {
    deliver(dockRows(doc: home, listedBand: band, bandAlpha: 1, overview: false))
    // Band disappears and reappears while a document is still parked and Dock alpha fades.
    XCTAssertEqual(deliver(dockRows(doc: parked, alpha: 1.0)), .restore)
    XCTAssertEqual(deliver(dockRows(doc: parked, alpha: 0.85)), .restore)
    XCTAssertEqual(deliver(dockRows(doc: parked, alpha: 0.70, listedBand: band)), .restore)
    XCTAssertEqual(deliver(dockRows(doc: parked, alpha: 0.60, listedBand: band)), .restore)
    // Only once the parked document moves back toward home does the return start.
    XCTAssertEqual(deliver(dockRows(doc: parked.offsetBy(dx: 20, dy: 0), alpha: 0.60, listedBand: band)), .start)
    XCTAssertNil(deliver(dockRows(doc: home, listedBand: band, bandAlpha: 1, overview: false)))
  }

  func testSeededBandVisibleAtAlphaOneOnFirstOverviewSampleStillRelists() {
    deliver(dockRows(listedBand: band, bandAlpha: 1, overview: false))
    // Sample 1 of Mission Control sees the band still at alpha 1 before TopNV hides it.
    XCTAssertEqual(deliver(dockRows(listedBand: band, bandAlpha: 1)), .restore)
    XCTAssertEqual(deliver(dockRows()), .restore)
    XCTAssertEqual(deliver(dockRows()), .restore)
    XCTAssertEqual(deliver(dockRows(listedBand: band, bandAlpha: 0)), .restore)
    XCTAssertEqual(deliver(dockRows(listedBand: band, bandAlpha: 0)), .start)
  }
}
