import XCTest
@testable import TopNVCore

final class RelativeLuminanceKeyTests: XCTestCase {
  // Apply the actual renderer matrix to a neutral pixel, including its output clamp.
  private func output(_ key: LuminanceKey, _ pixel: Float) -> Float {
    let row = key.matrix
    return min(1, max(0, (row[0] + row[1] + row[2]) * pixel + row[4]))
  }

  func testFiveLampKeysMapTheirBlackAndWhiteEndpoints() {
    let points: [(Float, Float)] = [(0.97, 0.15), (0.94, 0.15), (0.90, 0.15), (0.86, 0.15), (0.94, 0.30)]
    XCTAssertEqual(LampKeyPreset.choices.count, points.count)
    for (preset, points) in zip(LampKeyPreset.choices, points) {
      XCTAssertEqual(preset.key.blackPoint, points.0, accuracy: 1e-6)
      XCTAssertEqual(preset.key.whitePoint, points.1, accuracy: 1e-6)
      XCTAssertEqual(output(preset.key, points.0), 0, accuracy: 1e-6)
      XCTAssertEqual(output(preset.key, points.1), 1, accuracy: 1e-6)
    }
  }

  func testKeyFollowsTheSampledBackground() {
    for level in 55...95 {
      let background = Float(level) / 100
      let key = LuminanceKey.forBackdrop(backgroundLuma: background, relativeEnabled: true)
      XCTAssertEqual(output(key, background), 0)
      XCTAssertEqual(output(key, 0.93 * background), 0, accuracy: 1e-5)
      XCTAssertEqual(output(key, 0.2 * background), 1, accuracy: 1e-5)
      XCTAssertEqual(output(key, 0.15 * background), 1)
      XCTAssertEqual(output(key, 0.5 * background), 0.589, accuracy: 0.001)
      XCTAssertEqual(output(key, 0.8 * background), 0.178, accuracy: 0.001)
    }
  }

  func testKeyIsMonotoneAndClipsOutsideThePixelRange() {
    let key = LuminanceKey.forBackdrop(backgroundLuma: 0.8, relativeEnabled: true)
    let ramp = (-10...110).map { output(key, Float($0) / 100) }
    XCTAssertEqual(ramp.first, 1)
    XCTAssertEqual(ramp.last, 0)
    for (previous, next) in zip(ramp, ramp.dropFirst()) { XCTAssertGreaterThanOrEqual(previous, next) }
  }

  func testUnavailableOrInvalidSampleUsesProductionMatrix() {
    let unusable: [Float?] = [nil, .nan, .infinity, -.infinity, -1, 0, .leastNonzeroMagnitude, 1.01]
    for sample in unusable {
      XCTAssertEqual(LuminanceKey.forBackdrop(backgroundLuma: sample, relativeEnabled: true).matrix,
                     LuminanceKey.normal.matrix)
    }
  }

  func testLowBarMeanCanEraseAStatusGlyphThatTheOrdinaryKeyShows() {
    let relative = LuminanceKey.forBackdrop(backgroundLuma: 0.12, relativeEnabled: true)
    let glyph: Float = 0.15
    XCTAssertEqual(output(relative, glyph), 0)
    XCTAssertEqual(output(.normal, glyph), 0.68, accuracy: 0.001)
  }

  func testSwitchRestoresProductionEvenWithAValidSample() {
    let disabled = LuminanceKey.forBackdrop(backgroundLuma: 0.85, relativeEnabled: false)
    XCTAssertEqual(disabled.matrix, LuminanceKey.normal.matrix)
  }
}
