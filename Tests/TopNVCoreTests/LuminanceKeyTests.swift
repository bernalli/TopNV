import XCTest
@testable import TopNVCore

final class LuminanceKeyTests: XCTestCase {
  func testTheRevealedKeyIsChosenOnlyWhenTheDesktopIsRevealed() {
    XCTAssertEqual(LuminanceKey.choose(desktopRevealed: true), .revealed)
    XCTAssertEqual(LuminanceKey.choose(desktopRevealed: false), .normal)
  }

  /// Calibrated on screen: the revealed backdrop is darker, so its key turns black earlier.
  func testBlackAndWhitePointsOfTheTwoKeys() {
    XCTAssertEqual(LuminanceKey.normal.gain, 3)
    XCTAssertEqual(LuminanceKey.normal.cutoff, 0.21)
    XCTAssertEqual(LuminanceKey.revealed.gain, 6)
    XCTAssertEqual(LuminanceKey.revealed.cutoff, 0.2)
    XCTAssertGreaterThanOrEqual(LuminanceKey.normal.blackPoint, 0.30)
    XCTAssertLessThanOrEqual(LuminanceKey.normal.blackPoint, 0.45)
    XCTAssertGreaterThan(LuminanceKey.normal.blackPoint, LuminanceKey.revealed.blackPoint)
    XCTAssertGreaterThanOrEqual(LuminanceKey.normal.whitePoint, 0.03)
    XCTAssertLessThanOrEqual(LuminanceKey.revealed.blackPoint, 0.31)
    XCTAssertEqual(LuminanceKey.normal.blackPoint, 0.3767, accuracy: 1e-4)
    XCTAssertEqual(LuminanceKey.normal.whitePoint, 0.0433, accuracy: 1e-4)
    XCTAssertEqual(LuminanceKey.revealed.blackPoint, 0.2833, accuracy: 1e-4)
  }

  /// Production ships the linear key until a curve is chosen on the real menu bar.
  func testProductionKeysHaveNoCurve() {
    XCTAssertNil(LuminanceKey.normal.curve)
    XCTAssertNil(LuminanceKey.revealed.curve)
  }

  func testTheCurvesAreTheFilterBezier() {
    XCTAssertEqual(KeyCurve.soft.values, [0, 2.0 / 3.0, 1, 1])
    XCTAssertEqual(KeyCurve.strong.values, [0, 1, 1, 1])
    for step in 0...100 {
      let input = Double(step) / 100
      XCTAssertEqual(KeyCurve.soft.output(input), 1 - pow(1 - input, 2), accuracy: 1e-12)
      XCTAssertEqual(KeyCurve.strong.output(input), 1 - pow(1 - input, 3), accuracy: 1e-12)
    }
  }

  func testCurvesSaturateInputAndPreserveBrightness() {
    for curve in [KeyCurve.soft, .strong] {
      var previous = 0.0
      for step in -300...200 {
        let input = Double(step) / 100
        let t = min(max(input, 0), 1)
        let power = curve == .soft ? 2.0 : 3.0
        let output = curve.output(input)
        XCTAssertEqual(output, 1 - pow(1 - t, power), accuracy: 1e-12)
        XCTAssertGreaterThanOrEqual(output + 1e-12, previous)
        XCTAssertGreaterThanOrEqual(output + 1e-12, t)
        previous = output
      }
    }
  }

  func testTheOutputOfAKeyWithACurve() {
    let key = LuminanceKey.normal
    for curve in [nil, KeyCurve.soft, .strong] {
      func output(_ luma: Float) -> Double {
        LuminanceKey.output(luma: luma, gain: key.gain, cutoff: key.cutoff, curve: curve)
      }
      XCTAssertEqual(output(key.blackPoint), 0, accuracy: 1e-5)
      XCTAssertEqual(output(1), 0)
      XCTAssertEqual(output(key.whitePoint), 1, accuracy: 1e-5)
      XCTAssertGreaterThan(output(0), 0.98)
    }
    // A glyph at half opacity over a background at luma 0.6: luma 0.35.
    XCTAssertEqual(LuminanceKey.output(luma: 0.35, gain: 3, cutoff: 0.21, curve: nil), 0.08, accuracy: 1e-5)
    XCTAssertEqual(LuminanceKey.output(luma: 0.35, gain: 3, cutoff: 0.21, curve: .soft), 0.1536, accuracy: 1e-5)
    XCTAssertEqual(LuminanceKey.output(luma: 0.35, gain: 1.9, cutoff: 0.3, curve: .soft), 0.6462, accuracy: 1e-3)
  }

  func testTheMatrixKeysLumaFromTheWhitePointToTheBlackPoint() {
    for key in [LuminanceKey.normal, .revealed] {
      let matrix = key.matrix
      XCTAssertEqual(matrix.count, 20, "\(key)")
      XCTAssertEqual(Array(matrix[0..<5]), Array(matrix[5..<10]), "\(key)")
      XCTAssertEqual(Array(matrix[0..<5]), Array(matrix[10..<15]), "\(key)")
      XCTAssertEqual(Array(matrix[15..<20]), [0, 0, 0, 0, 1], "\(key)")
      XCTAssertEqual(matrix[3], 0, "\(key)")
      XCTAssertEqual(matrix[0] / matrix[1], 0.2126 / 0.7152, accuracy: 1e-5, "\(key)")
      XCTAssertEqual(matrix[2] / matrix[1], 0.0722 / 0.7152, accuracy: 1e-5, "\(key)")
      func output(gray luma: Float) -> Float {
        matrix[0] * luma + matrix[1] * luma + matrix[2] * luma + matrix[4]
      }
      XCTAssertEqual(output(gray: key.blackPoint), 0, accuracy: 1e-4, "\(key)")
      XCTAssertEqual(output(gray: key.whitePoint), 1, accuracy: 1e-4, "\(key)")
      XCTAssertEqual(output(gray: key.cutoff), 0.5, accuracy: 1e-4, "\(key)")
    }
  }
}
