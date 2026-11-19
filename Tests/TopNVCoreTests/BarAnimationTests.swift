import XCTest
@testable import TopNVCore

final class BarAnimationTests: XCTestCase {
  func testCatalogHasOneUnambiguousEntryPerHTMLVariant() throws {
    let durations = [
      "astra-sipario": 720, "astra-filo": 880, "astra-frecce": 620, "astra-respiro": 1120,
      "fable-scorrimento-calmo": 760, "fable-notch-allungata": 720,
      "fable-filo-tenda": 840, "fable-onda-lenta": 1150
    ]
    XCTAssertEqual(BarAnimation.allCases.count, durations.count)
    for (id, duration) in durations {
      let variant = try XCTUnwrap(BarAnimation(rawValue: id))
      XCTAssertEqual(variant.durationMS, Double(duration))
    }
    XCTAssertNil(BarAnimation(rawValue: "missing"))
    XCTAssertEqual(Set(BarAnimation.allCases.map(\.rawValue)).count, durations.count)
  }

  func testDisabledCornersReleaseTheThreeShorterAstraTracksAtTheirLastVisibleFrame() {
    XCTAssertEqual(BarAnimation.allCases.map { $0.durationMS(rounded: false) },
                   [560, 710, 490, 1120, 760, 720, 840, 1150])
    XCTAssertEqual(BarAnimation.allCases.map { $0.durationMS(rounded: true) },
                   [720, 880, 620, 1120, 760, 720, 840, 1150])
  }

  func testCurtainsKeepTheirDistinctNotchWidthsAndEasing() {
    func width(_ variant: BarAnimation, _ time: Double) -> Double {
      variant.frame(at: time, width: 1000, height: 30, notch: 150).halfWidth
    }
    XCTAssertEqual(width(.curtain, 0), 0)
    XCTAssertEqual(width(.calm, 0), 64)
    XCTAssertEqual(width(.curtain, 280), 250, accuracy: 0.001)
    XCTAssertEqual(width(.calm, 273.6), 282, accuracy: 0.001)
    XCTAssertEqual(BarAnimation.curtain.corner(at: 560, top: false).progress, 0)
    XCTAssertEqual(BarAnimation.calm.corner(at: 547.2, top: true).progress, 0)
  }

  func testCornerTreatmentsMatchTheReferenceOrder() {
    XCTAssertEqual(BarAnimation.allCases.map { $0.corner(at: 0, top: true).style },
                   [.fade, .slideFade, .growFade, .fade, .fade, .grow, .unfold, .diagonal])
  }

  func testTwoStrokeCapsuleHoldsAt54PercentWhileGlyphsWait() {
    let variant = BarAnimation.breath
    for time in [336.0, 400, 432] {
      let frame = variant.frame(at: time, width: 1000, height: 30, notch: 150)
      XCTAssertEqual(frame.halfWidth, 270, accuracy: 0.001)
      XCTAssertEqual(frame.glyphOpacity, 0)
    }
    XCTAssertEqual(variant.corner(at: 950, top: false).progress, 0)
    XCTAssertEqual(variant.corner(at: 1000, top: true).progress, 1)
  }

  func testThinStripsStayAtTheTopBeforeDescending() {
    let blind = BarAnimation.blind
    for time in [252.0, 280, 310.8] {
      let frame = blind.frame(at: time, width: 1000, height: 30, notch: 150)
      XCTAssertEqual(frame.halfWidth, 500, accuracy: 0.001)
      XCTAssertEqual(frame.height, 6, accuracy: 0.001)
    }
    XCTAssertEqual(BarAnimation.ink.frame(at: 426, width: 1000, height: 30, notch: 150).height, 5.4,
                   accuracy: 0.001)
    XCTAssertGreaterThan(blind.corner(at: 640, top: true).progress, 0)
    XCTAssertEqual(blind.corner(at: 640, top: false).progress, 0)
  }

  func testPointedFrontsLeadTheIndependentGlyphReveal() {
    let arrow = BarAnimation.arrows.frame(at: 80, width: 1000, height: 30, notch: 150)
    XCTAssertEqual(arrow.tip, 45)
    XCTAssertEqual(arrow.glyphHalfWidth, 0)
    let wave = BarAnimation.wave.frame(at: 230, width: 1000, height: 30, notch: 150)
    XCTAssertEqual(wave.tip, 30)
    XCTAssertEqual(wave.glyphHalfWidth, 64)
  }

  func testRoundedStretchPassesTheEdgeAndLightsTheMenuDuringSettling() {
    let frame = BarAnimation.stretch.frame(at: 504, width: 1000, height: 30, notch: 150)
    XCTAssertEqual(frame.halfWidth, 516.5, accuracy: 0.001)
    XCTAssertGreaterThan(frame.glyphOpacity, 0)
    XCTAssertLessThan(frame.glyphOpacity, 1)
    XCTAssertEqual(BarAnimation.stretch.corner(at: 324, top: true).progress, 0)
  }

  func testEveryVariantFinishesWithTheBarGlyphsAndBothCornerPairsVisible() {
    for variant in BarAnimation.allCases {
      let end = variant.durationMS
      let frame = variant.frame(at: end, width: 1000, height: 30, notch: 150)
      XCTAssertGreaterThanOrEqual(frame.halfWidth, 500)
      XCTAssertEqual(frame.height, 30)
      XCTAssertEqual(frame.glyphOpacity, 1)
      XCTAssertGreaterThanOrEqual(frame.glyphHalfWidth, 500)
      for top in [false, true] {
        XCTAssertEqual(variant.corner(at: 0, top: top).progress, 0)
        XCTAssertEqual(variant.corner(at: end, top: top).progress, 1)
      }
    }
  }
}
