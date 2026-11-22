import XCTest
@testable import TopNVCore

final class BarAnimationTests: XCTestCase {
  func testCatalogHasOneUnambiguousEntryPerHTMLVariant() throws {
    let durations = [
      "astra-sipario": 720, "astra-filo": 880, "astra-frecce": 620, "astra-respiro": 1120,
      "fable-scorrimento-calmo": 570, "fable-notch-allungata": 720,
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
                   [560, 710, 490, 1120, 570, 720, 840, 1150])
    XCTAssertEqual(BarAnimation.allCases.map { $0.durationMS(rounded: true) },
                   [720, 880, 620, 1120, 570, 720, 840, 1150])
  }

  func testCurtainsKeepTheirDistinctNotchWidthsAndEasing() {
    func width(_ variant: BarAnimation, _ time: Double) -> Double {
      variant.frame(at: time, width: 1000, height: 30, notch: 150).halfWidth
    }
    XCTAssertEqual(width(.curtain, 0), 0)
    XCTAssertEqual(width(.calm, 0), 64)
    XCTAssertEqual(width(.curtain, 280), 250, accuracy: 0.001)
    XCTAssertEqual(width(.calm, 205.2), 282, accuracy: 0.001)
    XCTAssertEqual(BarAnimation.curtain.corner(at: 560, top: false).progress, 0)
  }

  func testCalmWidthMovesEarlyAndAvoidsAMidpointSurge() {
    let variant = BarAnimation.calm
    func width(_ elapsed: Double) -> Double {
      2 * variant.frame(at: elapsed / ReturnTiming.durationMS * variant.durationMS,
                        width: 3024, height: 66, notch: 346).halfWidth
    }
    // In the build 20 recording, adjacent frames could be 25 ms apart.
    // Advance at least one slice per side early; keep each such step under 15% of the display.
    XCTAssertGreaterThan(width(25) - width(0), 96)
    for elapsed in stride(from: 0.0, through: 210, by: 1) {
      XCTAssertLessThan(width(elapsed + 25) - width(elapsed), 3024 * 0.15)
    }
  }

  func testAllCalmCornersReachHalfOpacityAtMidTravelAndFullOpacityAtArrival() {
    for top in [true, false] {
      let variant = BarAnimation.calm
      XCTAssertGreaterThan(variant.corner(at: 1000.0 / 60, top: top).progress, 0)
      XCTAssertEqual(variant.corner(at: 205.2, top: top).progress, 0.5, accuracy: 0.00001)
      XCTAssertEqual(variant.corner(at: 410.4, top: top).progress, 1)
    }
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

  /// The production entrance for any clock value and any notch, also outside its range.
  func testTheCalmEntranceOnlyGrowsFromTheNotchToTheEdgesForAnyClock() {
    let variant = BarAnimation.calm
    let end = variant.durationMS
    // The band arrives at 72% of the reference duration, together with the corners.
    let arrival = end * 0.72
    let times = [-Double.infinity, -1000, -1, 0] + stride(from: 1.0, through: end, by: 7)
      + [end, end + 1, 5000, .infinity]
    for (width, notch) in [(1512.0, 185.0), (1000, 150), (1000, 0), (1000, -40), (1000, 10), (1000, 1200), (0, 0)] {
      let half = width / 2
      let start = min(max(0, notch / 2 - width * 0.011), max(half, 0))
      var previous = (halfWidth: -Double.infinity, top: 0.0, bottom: 0.0)
      for time in times {
        let frame = variant.frame(at: time, width: width, height: 33, notch: notch)
        let top = variant.corner(at: time, top: true).progress
        let bottom = variant.corner(at: time, top: false).progress
        let context = "width \(width) notch \(notch) time \(time)"
        XCTAssertTrue(frame.halfWidth.isFinite && top.isFinite && bottom.isFinite, context)
        XCTAssertEqual(frame.height, 33, context)
        XCTAssertEqual(frame.glyphOpacity, 1, context)
        XCTAssertEqual(top, bottom, context)
        XCTAssertTrue((0...1).contains(top), context)
        XCTAssertGreaterThanOrEqual(top, previous.top, context)
        if notch <= width {
          XCTAssertGreaterThanOrEqual(frame.halfWidth, start - 1e-9, context)
          XCTAssertLessThanOrEqual(frame.halfWidth, half + 1e-9, context)
          XCTAssertGreaterThanOrEqual(frame.halfWidth, previous.halfWidth - 1e-9, context)
        }
        if time <= 0 {
          XCTAssertEqual(frame.halfWidth, max(0, notch / 2 - width * 0.011), accuracy: 1e-9, context)
          XCTAssertEqual(top, 0, context)
        }
        if time >= arrival + 1 { XCTAssertEqual(frame.halfWidth, half, accuracy: 1e-9, context) }
        if time >= arrival { XCTAssertEqual(top, 1, context) }
        previous = (frame.halfWidth, top, bottom)
      }
    }
  }

  func testAClockWithoutAValueNeverMovesAnyVariant() {
    for variant in BarAnimation.allCases {
      let frame = variant.frame(at: .nan, width: 1000, height: 30, notch: 150)
      XCTAssertTrue(frame.halfWidth.isFinite && frame.height.isFinite && frame.glyphOpacity.isFinite, variant.rawValue)
      for top in [false, true] {
        XCTAssertTrue((0...1).contains(variant.corner(at: .nan, top: top).progress), variant.rawValue)
      }
    }
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
