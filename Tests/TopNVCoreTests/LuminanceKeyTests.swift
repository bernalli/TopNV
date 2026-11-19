import XCTest
@testable import TopNVCore

final class LuminanceKeyTests: XCTestCase {
  func testBlackAndWhitePointsOfTheNormalKey() {
    XCTAssertEqual(LuminanceKey.normal.gain, 3)
    XCTAssertEqual(LuminanceKey.normal.cutoff, 0.21)
    XCTAssertGreaterThanOrEqual(LuminanceKey.normal.blackPoint, 0.30)
    XCTAssertLessThanOrEqual(LuminanceKey.normal.blackPoint, 0.45)
    XCTAssertGreaterThanOrEqual(LuminanceKey.normal.whitePoint, 0.03)
    XCTAssertEqual(LuminanceKey.normal.blackPoint, 0.3767, accuracy: 1e-4)
    XCTAssertEqual(LuminanceKey.normal.whitePoint, 0.0433, accuracy: 1e-4)
  }

  func testTheMatrixKeysLumaFromTheWhitePointToTheBlackPoint() {
    let key = LuminanceKey.normal
    let matrix = key.matrix
    XCTAssertEqual(matrix.count, 20)
    XCTAssertEqual(Array(matrix[0..<5]), Array(matrix[5..<10]))
    XCTAssertEqual(Array(matrix[0..<5]), Array(matrix[10..<15]))
    XCTAssertEqual(Array(matrix[15..<20]), [0, 0, 0, 0, 1])
    XCTAssertEqual(matrix[3], 0)
    XCTAssertEqual(matrix[0] / matrix[1], 0.2126 / 0.7152, accuracy: 1e-5)
    XCTAssertEqual(matrix[2] / matrix[1], 0.0722 / 0.7152, accuracy: 1e-5)
    func output(gray luma: Float) -> Float {
      matrix[0] * luma + matrix[1] * luma + matrix[2] * luma + matrix[4]
    }
    XCTAssertEqual(output(gray: key.blackPoint), 0, accuracy: 1e-4)
    XCTAssertEqual(output(gray: key.whitePoint), 1, accuracy: 1e-4)
    XCTAssertEqual(output(gray: key.cutoff), 0.5, accuracy: 1e-4)
  }
}
