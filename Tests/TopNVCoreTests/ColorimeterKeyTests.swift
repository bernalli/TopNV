import XCTest
@testable import TopNVCore

final class ColorimeterKeyTests: XCTestCase {
  // Apply the actual renderer matrix to a neutral pixel, including its output clamp.
  private func output(_ key: LuminanceKey, _ pixel: Float) -> Float {
    let row = key.matrix
    return min(1, max(0, (row[0] + row[1] + row[2]) * pixel + row[4]))
  }

  func testColorimeterGlyphPressedAndLightenOutputs() {
    let pixels: [Float] = [35, 60, 100, 150, 200, 213, 220, 223, 228, 229, 230, 232, 240, 255]
    let glyphs: [Double] = [229.9, 200.2, 158.7, 108.7, 49.2, 30.7, 20, 15.3, 7.2, 5.5, 3.9, 0.5, 0, 0]
    let composite: [Double] = [229.9, 200.2, 158.7, 108.7, 49.2, 38, 38, 38, 38, 38, 3.9, 0.5, 0, 0]
    for (index, pixel) in pixels.enumerated() {
      let input = pixel / 255
      let glyph = ColorimeterKey.curve.output(Double(output(ColorimeterKey.glyph, input))) * 255
      let pressed = Double(output(ColorimeterKey.threshold, input) * ColorimeterKey.pressedLevel * 255)
      XCTAssertEqual(glyph, glyphs[index], accuracy: 1)
      XCTAssertEqual(pressed, pixel <= 229 ? 38 : 0, accuracy: 0.01)
      XCTAssertEqual(max(glyph, pressed), composite[index], accuracy: 1)
    }
  }
}
