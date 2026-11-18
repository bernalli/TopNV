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
