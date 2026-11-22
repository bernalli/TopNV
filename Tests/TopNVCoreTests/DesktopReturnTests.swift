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
                    invalid: Bool = false, sliding: Bool = false, alpha: Double = 1,
                    surfaceNumber: CGWindowID = 21046, listedBand: CGRect? = nil,
                    bandID: CGWindowID = 55677, menu: MenuBarEvidence.Window? = nil) -> BandEntrance.Action? {
    var windows: [MenuBarEvidence.Window] = [
      menu ?? .init(owner: .windowServer, layer: 24, bounds: band),
      .init(owner: .application, layer: 0, bounds: bounds, number: number)
    ]
    if let listedBand {
      windows.append(.init(owner: .ownApp, layer: -2147483622, bounds: listedBand, alpha: 0, number: bandID))
    }
    if let surface {
      windows.append(.init(owner: .desktop, layer: surface, bounds: frame, isWindowManager: true,
                           alpha: alpha, number: surfaceNumber))
    }
    if sliding {
      windows.append(.init(owner: .desktop, layer: -1, bounds: frame.offsetBy(dx: 200, dy: 0), isWindowManager: true))
    }
    let list = invalid ? nil : windows
    let raw = MenuBarEvidence.evaluate(frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 33),
                                       bandFrame: band, windows: list)
    let result = tracker.resolve(raw, on: frame, windows: list, band: (bandID, band))
    return entrance.update(.sample, enabled: true, samples: [1: .init(result)], reduceMotion: false)[1]
  }

  func testRelistedHiddenBandStartsBeforeOpaqueOverviewEnds() {
    _ = step(home, surface: nil)
    XCTAssertEqual(step(home, surface: 19, listedBand: band), .restore)
    XCTAssertEqual(step(home, surface: 19), .restore)
    XCTAssertEqual(step(home, surface: 19), .restore)
    XCTAssertEqual(step(home, surface: 19, listedBand: band), .restore)
    XCTAssertEqual(step(home, surface: 19, listedBand: band), .start)
    XCTAssertNil(step(home, surface: 19, listedBand: band))
    XCTAssertNil(step(home, surface: nil, listedBand: band))
  }

  func testBandRelistingRequiresEstablishedAbsenceAndStableIdentities() {
    _ = step(home, surface: nil)
    for _ in 0..<3 { XCTAssertEqual(step(home, surface: 19), .restore) }
    XCTAssertEqual(step(home, surface: 19, listedBand: band), .restore)
    XCTAssertEqual(step(home, surface: 19), .restore)
    XCTAssertEqual(step(home, surface: 19, listedBand: band), .restore)
    for _ in 0..<2 { XCTAssertEqual(step(home, surface: 19), .restore) }
    XCTAssertEqual(step(home, surface: 19, listedBand: band.offsetBy(dx: 60, dy: 0)), .restore)
    XCTAssertEqual(step(home, surface: 19, listedBand: band), .restore)
    for _ in 0..<2 { XCTAssertEqual(step(home, surface: 19), .restore) }
    XCTAssertEqual(step(home, surface: 19, listedBand: band, bandID: 55700), .restore)
    for _ in 0..<2 { XCTAssertEqual(step(home, surface: 19, bandID: 55700), .restore) }
    XCTAssertEqual(step(home, surface: 19, surfaceNumber: 9, listedBand: band, bandID: 55700), .restore)
  }

  func testOverviewOpacityReboundCancelsBandReturnWithoutRearmingFromPersistentListing() {
    _ = step(home, surface: nil)
    _ = step(home, surface: 19, listedBand: band)
    _ = step(home, surface: 19)
    _ = step(home, surface: 19)
    _ = step(home, surface: 19, listedBand: band)
    XCTAssertEqual(step(home, surface: 19, listedBand: band), .start)
    XCTAssertNil(step(home, surface: 19, alpha: 0.8, listedBand: band))
    XCTAssertEqual(step(home, surface: 19, listedBand: band), .restore)
    XCTAssertEqual(step(home, surface: 19, listedBand: band), .restore)
    XCTAssertEqual(step(home, surface: 19, listedBand: band), .restore)
    XCTAssertEqual(step(home, surface: nil, listedBand: band), .start)
  }

  func testShrinkingThumbnailCancelsBandReturnWhileBandStaysListed() {
    let small = home.insetBy(dx: 160, dy: 140)
    let growing = home.insetBy(dx: 145, dy: 125)
    _ = step(home, surface: nil)
    _ = step(small, surface: 19, listedBand: band)
    _ = step(small, surface: 19)
    _ = step(small, surface: 19)
    _ = step(small, surface: 19, listedBand: band)
    XCTAssertEqual(step(small, surface: 19, listedBand: band), .start)
    XCTAssertNil(step(growing, surface: 19, listedBand: band))
    XCTAssertEqual(step(small, surface: 19, listedBand: band), .restore)
  }

  func testOverviewBrighteningReversesRelistingWithoutAPriorFade() {
    _ = step(home, surface: nil)
    for listed: CGRect? in [band, nil, nil, band] {
      XCTAssertEqual(step(home, surface: 19, alpha: 0.8, listedBand: listed), .restore)
    }
    XCTAssertEqual(step(home, surface: 19, alpha: 0.8, listedBand: band), .start)
    XCTAssertNil(step(home, surface: 19, alpha: 0.805, listedBand: band))
    XCTAssertEqual(step(home, surface: 19, alpha: 0.95, listedBand: band), .restore)
    XCTAssertEqual(step(home, surface: 19, alpha: 0.95, listedBand: band), .restore)
  }

  func testOverviewThumbnailShrinkingReversesRelistingWithoutPriorGrowth() {
    let thumbnail = home.insetBy(dx: 145, dy: 125)
    _ = step(home, surface: nil)
    for listed: CGRect? in [band, nil, nil, band] {
      XCTAssertEqual(step(thumbnail, surface: 19, listedBand: listed), .restore)
    }
    XCTAssertEqual(step(thumbnail, surface: 19, listedBand: band), .start)
    XCTAssertNil(step(thumbnail.insetBy(dx: 0.5, dy: 0.5), surface: 19, listedBand: band))
    let smaller = thumbnail.insetBy(dx: 15, dy: 15)
    XCTAssertEqual(step(smaller, surface: 19, listedBand: band), .restore)
    XCTAssertEqual(step(smaller, surface: 19, listedBand: band), .restore)
  }

  func testBandRelistingRequiresAVisibleMenuOnTheSameDisplay() {
    let menus: [MenuBarEvidence.Window] = [
      .init(owner: .windowServer, layer: 24, bounds: band, alpha: 0),
      .init(owner: .windowServer, layer: 3, bounds: band),
      .init(owner: .windowServer, layer: 24, bounds: band.offsetBy(dx: frame.width, dy: 0))
    ]
    for menu in menus {
      tracker = DesktopReturn()
      entrance = BandEntrance()
      _ = step(home, surface: nil)
      _ = step(home, surface: 19, listedBand: band)
      _ = step(home, surface: 19)
      _ = step(home, surface: 19)
      XCTAssertEqual(step(home, surface: 19, listedBand: band, menu: menu), .restore)
      XCTAssertEqual(step(home, surface: 19, listedBand: band, menu: menu), .restore)
      XCTAssertEqual(step(home, surface: 19, listedBand: band), .restore)
      XCTAssertEqual(step(home, surface: 19, listedBand: band), .restore)
      XCTAssertEqual(step(home, surface: nil, listedBand: band), .start)
    }
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

  func testFallingSystemSurfaceStartsBeforeDisappearanceWithoutMovingDocuments() {
    for layer in [18, 19] {
      _ = step(home, surface: nil)
      XCTAssertEqual(step(home, surface: layer, alpha: 0.5), .restore)
      XCTAssertEqual(step(home, surface: layer, alpha: 0.96), .restore)
      XCTAssertEqual(step(home, surface: layer, alpha: 0.955), .restore)
      XCTAssertEqual(step(home, surface: layer, alpha: 0.90), .start)
      XCTAssertNil(step(home, surface: layer, alpha: 0.90))
      XCTAssertEqual(step(home, surface: layer, alpha: 0.97), .restore)
      _ = step(home, surface: nil)
    }
  }

  func testFallingShowDesktopSurfaceKeepsKnownParkedWindowHiddenUntilItReturns() {
    _ = step(home, surface: nil)
    XCTAssertEqual(step(parked, surface: 18, alpha: 0.60), .restore)
    XCTAssertEqual(step(parked, surface: 18, alpha: 0.58), .restore)
    XCTAssertEqual(step(parked, surface: nil), .restore)
    XCTAssertEqual(step(parked, surface: 18, alpha: 0.62), .restore)
    XCTAssertEqual(step(home, surface: 18, alpha: 0.62), .start)
    XCTAssertNil(step(home, surface: nil))
  }

  func testFadingOverviewStartsWhileAKnownThumbnailIsStill() {
    let thumbnail = home.insetBy(dx: 160, dy: 140)
    _ = step(home, surface: nil)
    XCTAssertEqual(step(thumbnail, surface: 19), .restore)
    XCTAssertEqual(step(thumbnail, surface: nil), .restore)
    XCTAssertEqual(step(thumbnail, surface: 19, alpha: 0.8), .start)
    XCTAssertNil(step(thumbnail, surface: nil))
    XCTAssertNil(step(thumbnail, surface: 19, alpha: 0.75))
  }

  func testNewSurfaceIdentityCannotInheritThePreviousFade() {
    for (layer, number) in [(18, CGWindowID(21046)), (19, CGWindowID(21047))] {
      _ = step(home, surface: nil)
      XCTAssertEqual(step(home, surface: 19, alpha: 0.96), .restore)
      XCTAssertEqual(step(home, surface: 19, alpha: 0.90), .start)
      XCTAssertEqual(step(home, surface: layer, alpha: 0.80, surfaceNumber: number), .restore)
      XCTAssertEqual(step(home, surface: layer, alpha: 0.79, surfaceNumber: number), .restore)
      XCTAssertEqual(step(home, surface: layer, alpha: 0.77, surfaceNumber: number), .start)
      _ = step(home, surface: nil)
    }
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
