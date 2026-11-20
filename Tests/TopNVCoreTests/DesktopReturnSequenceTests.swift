import CoreGraphics
import XCTest
@testable import TopNVCore

/// Sequences that a healthy window list does not produce, and the limits of the early return.
final class DesktopReturnSequenceTests: XCTestCase {
  private typealias Action = BandEntrance.Action
  private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let band = CGRect(x: 0, y: 949, width: 1512, height: 33)
  private let home = CGRect(x: 264, y: 95, width: 832, height: 769)
  private let parked = CGRect(x: -820, y: 166, width: 832, height: 769)
  private let thumbnail = CGRect(x: 300, y: 250, width: 430, height: 397)
  private var tracker = DesktopReturn()
  private var entrance = BandEntrance()
  private var revealed = false

  private struct Surface {
    var layer: Int
    var number: CGWindowID = 21046
    var alpha = 1.0
  }

  private func document(_ bounds: CGRect, _ number: CGWindowID? = 20978, layer: Int = 0,
                        alpha: Double = 1) -> MenuBarEvidence.Window {
    .init(owner: .application, layer: layer, bounds: bounds, alpha: alpha, number: number)
  }

  private func resolve(_ tracker: inout DesktopReturn, _ documents: [MenuBarEvidence.Window],
                       surface: Surface?, menu: Bool) -> MenuBarEvidence.Result {
    var windows = documents
    if menu { windows.append(.init(owner: .windowServer, layer: 24, bounds: band)) }
    if let surface {
      windows.append(.init(owner: .desktop, layer: surface.layer, bounds: frame, isWindowManager: true,
                           alpha: surface.alpha, number: surface.number))
    }
    let raw = MenuBarEvidence.evaluate(frame: frame, visibleFrame: frame.insetBy(dx: 0, dy: 33),
                                       bandFrame: band, windows: windows)
    return tracker.resolve(raw, on: frame, windows: windows)
  }

  @discardableResult
  private func step(_ documents: [MenuBarEvidence.Window], surface: Int?, surfaceNumber: CGWindowID = 21046,
                    menu: Bool = true, alpha: Double = 1) -> Action? {
    let shown = surface.map { Surface(layer: $0, number: surfaceNumber, alpha: alpha) }
    let result = resolve(&tracker, documents, surface: shown, menu: menu)
    revealed = result.desktopRevealed
    return entrance.update(.sample, enabled: true, samples: [1: .init(result)], reduceMotion: false)[1]
  }

  private func reveal(_ away: CGRect, surface: Int = 18) {
    XCTAssertNil(step([document(home)], surface: nil))
    XCTAssertEqual(step([document(away)], surface: surface), .restore)
  }

  func testOneMissingSurfaceDuringAReturnNeitherCancelsNorReplays() {
    reveal(parked)
    XCTAssertEqual(step([document(parked.offsetBy(dx: 60, dy: 0))], surface: 18), .start)
    XCTAssertNil(step([document(parked.offsetBy(dx: 200, dy: 0))], surface: nil))
    XCTAssertNil(step([document(parked.offsetBy(dx: 400, dy: 0))], surface: 18))
    XCTAssertNil(step([document(home)], surface: 18))
    XCTAssertNil(step([document(home)], surface: nil))
    XCTAssertNil(step([document(home)], surface: nil))
    // The next reveal starts from a clean state.
    XCTAssertEqual(step([document(parked)], surface: 18, surfaceNumber: 21050), .restore)
    XCTAssertEqual(step([document(home)], surface: nil), .start)
    XCTAssertNil(step([document(home)], surface: nil))
  }

  func testAReversalAfterAMissingSurfaceStillHidesTheBand() {
    reveal(parked)
    XCTAssertEqual(step([document(parked.offsetBy(dx: 60, dy: 0))], surface: 18), .start)
    XCTAssertNil(step([document(parked.offsetBy(dx: 80, dy: 0))], surface: nil))
    XCTAssertEqual(step([document(parked)], surface: 18), .restore)
  }

  func testOneMissingSurfaceWhileAThumbnailGrowsNeitherCancelsNorReplays() {
    reveal(home.insetBy(dx: 160, dy: 140), surface: 19)
    XCTAssertEqual(step([document(home.insetBy(dx: 145, dy: 125))], surface: 19), .start)
    XCTAssertNil(step([document(home.insetBy(dx: 60, dy: 50))], surface: nil))
    XCTAssertNil(step([document(home.insetBy(dx: 20, dy: 15))], surface: 19))
    XCTAssertNil(step([document(home)], surface: 19))
    XCTAssertNil(step([document(home)], surface: nil))
    XCTAssertNil(step([document(home)], surface: nil))
    // The next overview starts from a clean state, even on the same surface.
    XCTAssertEqual(step([document(thumbnail)], surface: 19), .restore)
    XCTAssertEqual(step([document(home)], surface: nil), .start)
  }

  func testAThumbnailThatShrinksAgainAfterAMissingSurfaceStillHidesTheBand() {
    let small = home.insetBy(dx: 160, dy: 140)
    reveal(small, surface: 19)
    XCTAssertEqual(step([document(home.insetBy(dx: 145, dy: 125))], surface: 19), .start)
    XCTAssertNil(step([document(home.insetBy(dx: 145, dy: 125))], surface: nil))
    XCTAssertEqual(step([document(small)], surface: 19), .restore)
  }

  func testOneMissingSurfaceWhileTheOverviewFadesNeitherCancelsNorReplays() {
    reveal(home, surface: 19)
    XCTAssertEqual(step([document(home)], surface: 19, alpha: 0.8), .start)
    XCTAssertNil(step([document(home)], surface: nil))
    XCTAssertNil(step([document(home)], surface: 19, alpha: 0.4))
    XCTAssertNil(step([document(home)], surface: nil))
    XCTAssertNil(step([document(home)], surface: nil))
    // The next overview starts from a clean state, even on the same surface: a surface that
    // has not been seen opaque again is not fading.
    XCTAssertEqual(step([document(home)], surface: 19, alpha: 0.4), .restore)
    XCTAssertEqual(step([document(home)], surface: nil), .start)
  }

  func testAnOverviewOpaqueAgainAfterAMissingSurfaceStillHidesTheBand() {
    reveal(home, surface: 19)
    XCTAssertEqual(step([document(home)], surface: 19, alpha: 0.8), .start)
    XCTAssertNil(step([document(home)], surface: nil))
    XCTAssertEqual(step([document(home)], surface: 19), .restore)
  }

  func testTwoSamplesWithoutTheSurfaceAlwaysEndTheReveal() {
    reveal(parked)
    XCTAssertEqual(step([document(parked)], surface: nil), .restore)
    XCTAssertEqual(step([document(parked)], surface: nil), .start)
    XCTAssertFalse(revealed)
  }

  func testAnotherDocumentStillParkedDoesNotCancelAReturnWhenTheSurfaceLeaves() {
    let otherHome = CGRect(x: 900, y: 200, width: 500, height: 400)
    let otherParked = CGRect(x: 1500, y: 200, width: 500, height: 400)
    XCTAssertNil(step([document(home), document(otherHome, 7)], surface: nil))
    XCTAssertEqual(step([document(parked), document(otherParked, 7)], surface: 18), .restore)
    XCTAssertEqual(step([document(parked.offsetBy(dx: 60, dy: 0)), document(otherParked, 7)], surface: 18), .start)
    XCTAssertNil(step([document(home), document(otherParked, 7)], surface: nil))
    XCTAssertNil(step([document(home), document(otherHome, 7)], surface: nil))
  }

  func testARepeatedWindowNumberIsNoIdentity() {
    for (layer, away) in [(18, parked), (19, thumbnail)] {
      tracker = DesktopReturn()
      entrance = BandEntrance()
      XCTAssertNil(step([document(home)], surface: nil))
      XCTAssertEqual(step([document(away), document(home)], surface: layer), .restore, "\(layer)")
      XCTAssertEqual(step([document(home), document(away)], surface: layer), .restore, "\(layer)")
      XCTAssertEqual(step([document(home)], surface: layer), .restore, "\(layer)")
      // Listed twice on the desktop, the number has no ordinary position either.
      XCTAssertEqual(step([document(home), document(home)], surface: nil), .start, "\(layer)")
      XCTAssertEqual(step([document(away)], surface: layer), .restore, "\(layer)")
      XCTAssertEqual(step([document(home)], surface: layer), .restore, "\(layer)")
    }
  }

  func testDocumentsWithoutIdentityOrSubstanceAreIgnored() {
    let ignored: [(CGRect) -> MenuBarEvidence.Window] = [
      { self.document($0, nil) },
      { self.document($0, layer: 3) },
      { self.document($0, layer: -1) },
      { self.document($0, alpha: 0) },
      { .init(owner: .desktop, layer: 0, bounds: $0, number: 20978) },
      { .init(owner: .ownApp, layer: 0, bounds: $0, number: 20978) }
    ]
    for make in ignored {
      for (layer, away) in [(18, parked), (19, thumbnail)] {
        tracker = DesktopReturn()
        entrance = BandEntrance()
        XCTAssertNil(step([make(home)], surface: nil))
        XCTAssertEqual(step([make(away)], surface: layer), .restore)
        XCTAssertEqual(step([make(away.offsetBy(dx: 60, dy: 0))], surface: layer), .restore)
        XCTAssertEqual(step([make(home)], surface: layer), .restore)
        XCTAssertEqual(step([make(home)], surface: nil), .start)
      }
    }
  }

  func testAResizedDocumentIsNotAReturnFromShowDesktop() {
    reveal(parked)
    var resized = parked.offsetBy(dx: 60, dy: 0)
    resized.size.width += 40
    XCTAssertEqual(step([document(resized)], surface: 18), .restore)
    XCTAssertEqual(step([document(home)], surface: nil), .start)
  }

  func testADocumentSlidingAlongTheEdgeIsNotAReturn() {
    reveal(parked)
    // 1.1 points nearer to its desktop position: inside the two points of tolerance.
    XCTAssertEqual(step([document(parked.offsetBy(dx: 6, dy: 54))], surface: 18), .restore)
    XCTAssertEqual(step([document(parked.offsetBy(dx: 12, dy: 54))], surface: 18), .start)
  }

  func testOnlyTheKnownSurfacesStartEarly() {
    for layer in [0, 3, 17, 20, 24] {
      for away in [parked, thumbnail] {
        tracker = DesktopReturn()
        entrance = BandEntrance()
        reveal(away, surface: layer)
        XCTAssertEqual(step([document(parked.offsetBy(dx: 60, dy: 0))], surface: layer), .restore, "\(layer)")
        XCTAssertEqual(step([document(home)], surface: layer), .restore, "\(layer)")
        XCTAssertEqual(step([document(home)], surface: layer, alpha: 0.5), .restore, "\(layer)")
        XCTAssertEqual(step([document(home)], surface: nil), .start, "\(layer)")
      }
    }
  }

  func testANewSurfaceForgetsTheDeparturesSeenUnderTheOldOne() {
    reveal(parked)
    XCTAssertEqual(step([document(parked.offsetBy(dx: 60, dy: 0))], surface: 18, surfaceNumber: 21050), .restore)
    XCTAssertEqual(step([document(home)], surface: nil), .start)
  }

  func testANewOverviewSurfaceIsNotFadingUntilItHasBeenOpaque() {
    reveal(home, surface: 19)
    XCTAssertEqual(step([document(home)], surface: 19, surfaceNumber: 21050, alpha: 0.8), .restore)
    XCTAssertEqual(step([document(home)], surface: nil), .start)
  }

  func testAFullSizeWindowFartherFromItsDesktopPositionIsNotAReturnFromMissionControl() {
    reveal(thumbnail, surface: 19)
    // The thumbnail was 168 points from the desktop position; this window is 400 points away.
    XCTAssertEqual(step([document(home.offsetBy(dx: 400, dy: 0))], surface: 19), .restore)
    XCTAssertEqual(step([document(home)], surface: 19), .start)
  }

  func testAWindowNarrowedAtFullHeightIsNotAMissionControlThumbnail() {
    var narrow = home
    narrow.size.width -= 300
    reveal(narrow, surface: 19)
    XCTAssertEqual(step([document(home)], surface: 19), .restore)
    XCTAssertEqual(step([document(home)], surface: nil), .start)
  }

  func testNoEarlyReturnWhileTheMenuBarIsAway() {
    XCTAssertNil(step([document(home)], surface: nil))
    XCTAssertEqual(step([document(parked)], surface: 18, menu: false), .restore)
    XCTAssertEqual(step([document(parked.offsetBy(dx: 60, dy: 0))], surface: 18, menu: false), .restore)
    XCTAssertEqual(step([document(home)], surface: nil), .start)
  }

  func testADocumentCentredOutsideTheDisplayIsNotEvidence() {
    let edge = CGRect(x: -500, y: 95, width: 832, height: 769)
    XCTAssertNil(step([document(edge)], surface: nil))
    XCTAssertEqual(step([document(parked)], surface: 18), .restore)
    XCTAssertEqual(step([document(parked.offsetBy(dx: 60, dy: 0))], surface: 18), .restore)
    XCTAssertEqual(step([document(edge)], surface: nil), .start)
  }
}

extension DesktopReturnSequenceTests {
  /// Any order of samples: the band is never held hidden without a surface for two samples,
  /// an unknown surface always hides it, one return starts at most one entrance, and the
  /// order of the documents in the window list never changes the outcome.
  func testHostileOrderingsKeepTheInvariants() {
    var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    func next(_ bound: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int((seed >> 33) % UInt64(bound))
    }
    let places = [home, parked, parked.offsetBy(dx: 60, dy: 0), thumbnail, home.offsetBy(dx: 40, dy: 0),
                  home.insetBy(dx: 160, dy: 140), home.insetBy(dx: 145, dy: 125),
                  CGRect(x: 1500, y: 300, width: 832, height: 769)]
    let layers: [Int?] = [nil, nil, 18, 18, 19, 19, 3]
    let alphas = [1, 1, 0.8, 0.4]
    var mirror = DesktopReturn()
    var withoutSurface = 0
    var lastAction: Action?
    for index in 0..<6000 {
      let layer = layers[next(layers.count)]
      var documents = [document(places[next(places.count)]), document(places[next(places.count)], 7)]
      if next(12) == 0 { documents.append(document(places[next(places.count)])) }
      if next(15) == 0 { documents.removeFirst() }
      let number: CGWindowID = next(8) == 0 ? 21050 : 21046
      let alpha = alphas[next(alphas.count)]
      let menu = next(10) != 0
      let action = step(documents, surface: layer, surfaceNumber: number, menu: menu, alpha: alpha)
      let shown = layer.map { Surface(layer: $0, number: number, alpha: alpha) }
      let mirrored = resolve(&mirror, documents.reversed(), surface: shown, menu: menu).desktopRevealed
      XCTAssertEqual(mirrored, revealed, "sample \(index)")
      withoutSurface = layer == nil ? withoutSurface + 1 : 0
      if withoutSurface >= 2 { XCTAssertFalse(revealed, "sample \(index)") }
      if layer == 3 { XCTAssertTrue(revealed, "sample \(index)") }
      if action == .start { XCTAssertNotEqual(lastAction, .start, "sample \(index)") }
      if let action { lastAction = action }
    }
  }
}
