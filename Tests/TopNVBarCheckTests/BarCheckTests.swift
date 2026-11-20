import CoreGraphics
import Foundation
import ImageIO
import TopNVBarCheck
import UniformTypeIdentifiers
import XCTest

final class BarCheckTests: XCTestCase {
  private typealias RGB = SIMD3<UInt8>
  private let black: RGB = [0, 0, 0]
  private let background: RGB = [226, 228, 226]
  private let zone = TimeZone(secondsFromGMT: 3600)!
  private let instant = "01:00:00.250"

  private func summary(_ bottom: Int = 70, display: Int = 2, size: String = "20x80", band: String = "on") -> String {
    "display=\(display) scene=desktop part=summary band=\(band) screenPx=\(size) scale=2 blackBottom=\(bottom)"
  }

  private func record(_ message: String, at time: String = "01:00:00.250") -> String {
    "2024-01-01 \(time) I  TopNV[123:456] [TopNV:BarSurface] \(message)"
  }

  // Supply storage in PNG scanline order, independently of drawing coordinates.
  private func image(width: Int = 20, height: Int = 80, pixel: (Int, Int) -> RGB) throws -> CGImage {
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space, bitmapInfo: info))
    let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
    for row in 0..<height {
      for column in 0..<width {
        let offset = (row * width + column) * 4
        let color = pixel(column, row)
        bytes[offset] = color.x
        bytes[offset + 1] = color.y
        bytes[offset + 2] = color.z
        bytes[offset + 3] = 255
      }
    }
    return try XCTUnwrap(context.makeImage())
  }

  private func arguments(_ image: CGImage, log: [String]) throws -> [String] {
    let files = FileManager.default
    let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try files.createDirectory(at: directory, withIntermediateDirectories: false)
    addTeardownBlock { try FileManager.default.removeItem(at: directory) }
    let capture = directory.appendingPathComponent("capture.png")
    let logURL = directory.appendingPathComponent("registry.log")
    let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(capture as CFURL, UTType.png.identifier as CFString,
                                                               1, nil))
    CGImageDestinationAddImage(writer, image, nil)
    guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
    try files.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_704_067_200.25)],
                            ofItemAtPath: capture.path)
    try log.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
    return ["--capture", capture.path, "--log", logURL.path]
  }

  func testBlackRowsDownToBlackBottomGiveOK() throws {
    let capture = try image { _, row in row < 70 ? black : background }
    let result = BarCheck.run(arguments: try arguments(capture, log: [record(summary())]), timeZone: zone)
    XCTAssertEqual(result.line, "OK rows 0-69 black; row 70 background (0.892); display 2, scene desktop, MISMATCH 0")
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertFalse(result.usage)
  }

  func testALightBandBelowTheMenuGivesFailWithItsRows() throws {
    let capture = try image { _, row in
      if row < 66 { return black }
      return row < 70 ? [169, 171, 169] : background
    }
    let result = BarCheck.run(arguments: try arguments(capture, log: [record(summary())]), timeZone: zone)
    XCTAssertEqual(result.exitCode, 1)
    XCTAssertTrue(result.line.contains("measured black 0-65"))
    XCTAssertTrue(result.line.contains("66=0.668 67=0.668 68=0.668 69=0.668"))
    XCTAssertTrue(result.line.contains("row 70=0.892"))
    let log = BarCheck.parseLog(record(summary()), timeZone: zone)
    let entry = try XCTUnwrap(log.summaries.first)
    let allLight = BarCheck.verdict(medians: Array(repeating: 0.8, count: 74), summary: entry, mismatches: 0)
    XCTAssertTrue(allLight.line.contains("measured black none"))
    XCTAssertTrue(allLight.line.contains("11=0.800 … (+58)"))
  }

  func testGlyphsInTheMenuRowsDoNotMoveTheMedian() throws {
    let capture = try image { column, row in
      if (10...50).contains(row), column < 6 { return [255, 255, 255] }
      return row < 70 ? black : background
    }
    let result = BarCheck.run(arguments: try arguments(capture, log: [record(summary())]), timeZone: zone)
    XCTAssertEqual(result.exitCode, 0)
    let halfWhite = try image(width: 2, height: 1) { column, _ in column == 0 ? [255, 255, 255] : black }
    XCTAssertEqual(BarCheck.rowMedians(halfWhite, rows: 0..<1), [0])
  }

  func testABlackRowBelowBlackBottomGivesDoubt() throws {
    let capture = try image { _, row in row <= 70 ? black : background }
    let result = BarCheck.run(arguments: try arguments(capture, log: [record(summary())]), timeZone: zone)
    XCTAssertTrue(result.line.hasPrefix("DUBIOUS rows 0-70 black"))
    XCTAssertTrue(result.line.contains("retake the screenshot"))
    XCTAssertEqual(result.exitCode, 3)
    let entry = try XCTUnwrap(BarCheck.parseLog(record(summary(1)), timeZone: zone).summaries.first)
    XCTAssertEqual(BarCheck.verdict(medians: [0.05, 0.051], summary: entry, mismatches: 0).exitCode, 0)
  }

  func testTheLastSummaryBeforeTheCaptureOfTheSameSizeIsUsed() throws {
    let capture = try image(width: 3024, height: 1964) { _, row in row == 0 ? black : background }
    let first = summary(2, display: 1, size: "3024x1964")
    let selected = summary(1, display: 3, size: "3024x1964")
    let lines = [record(first), record(selected, at: "01:00:00.249"),
                 record(summary(0, size: "1920x1080")), record(first, at: "01:00:00.251")]
    let result = BarCheck.run(arguments: try arguments(capture, log: lines), timeZone: zone)
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.line.contains("display 3,"))
  }

  func testMalformedLogLinesAreIgnored() {
    let message = summary(7)
    let part = "display=2 scene=desktop part=edge px=0,-1,20,4 alpha=0.333 level=27 window=9 mask=empty"
    let listing = part + " listed=0,0,20,4/1"
    let mismatch = listing + " MISMATCH"
    let valid = [message, part, listing, mismatch, part.replacingOccurrences(of: "part=edge", with: "part=lamp")].map { record($0) }
    let prefixes = valid.flatMap { line in
      line.indices.map { String(line[..<$0]) }.filter { !valid.contains($0) }
    }
    let changes = [
      ("display=2", "display=-1"), ("display=2", "display=4294967296"), ("scene=desktop", "scene=invalid"),
      ("band=on", "band=on band=on"), ("band=on", "band=yes"), ("scale=2", "scale=NaN"),
      ("scale=2", "scale=-1"), ("scale=2", "scale=0"), ("20x80", "0x80"), ("blackBottom=7", "blackBottom=-1"),
      ("blackBottom=7", "blackBottom=x"), ("scale=2", " scale=2"), ("scale=2", "extra=1 scale=2"),
      ("TopNV:BarSurface", "TopNV:Other"), ("2024-01-01", "2024-02-30"),
      ("band=on screenPx=20x80", "screenPx=20x80 band=on"), ("scale=2 blackBottom=7", "blackBottom=7 scale=2"),
      ("display=2 scene=desktop", "scene=desktop display=2")
    ]
    let malformed = prefixes + changes.map { valid[0].replacingOccurrences(of: $0.0, with: $0.1) }
      + [record(part + " MISMATCH"), record(mismatch + " extra=1"),
         record(mismatch.replacingOccurrences(of: "alpha=0.333", with: "alpha=NaN")),
         record(listing.replacingOccurrences(of: "level=27 window=9", with: "window=9 level=27"))]
    let log = BarCheck.parseLog((malformed + valid).joined(separator: "\n"), timeZone: zone)
    XCTAssertEqual(log.ignoredLines, malformed.count)
    XCTAssertEqual(log.summaries.map(\.blackBottom), [7])
    XCTAssertEqual(log.mismatches[2]?.count, 1)
  }

  func testNoMatchingDisplayOrInactiveBarFails() throws {
    let capture = try image { _, _ in black }
    let missing = BarCheck.run(arguments: try arguments(capture, log: [record(summary(size: "19x80"))]), timeZone: zone)
    XCTAssertEqual(missing.exitCode, 1)
    XCTAssertEqual(missing.line, "FAIL no registry line for a 20x80 capture before 01:00:00")
    let inactiveArgs = try arguments(capture, log: [record(summary(0, band: "off"))])
    let inactive = BarCheck.run(arguments: inactiveArgs, timeZone: zone)
    XCTAssertEqual(inactive.exitCode, 1)
    XCTAssertEqual(inactive.line, "FAIL black bar was inactive (display 2, scene desktop, band off)")
    let outside = BarCheck.run(arguments: try arguments(capture, log: [record(summary(80))]), timeZone: zone)
    XCTAssertEqual(outside.exitCode, 1)
    XCTAssertTrue(outside.line.contains("blackBottom 80"))
  }

  func testArgumentsRejectUnknownRepeatedOrMissingOptions() {
    for args in [[], ["--log"], ["--log", "x"], ["--log", "x", "--log", "y"], ["--log", "--capture", "y"],
                 ["--log", "x", "--capture"], ["--unknown", "x", "--capture", "y"],
                 ["--log", "x", "--capture", "y", "extra"]] {
      let result = BarCheck.run(arguments: args, timeZone: zone)
      XCTAssertTrue(result.usage)
      XCTAssertEqual(result.line, "bar-check: usage: bar-check --log <file> --capture <png>")
      XCTAssertEqual(result.exitCode, 2)
    }
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
    let result = BarCheck.run(arguments: ["--log", path, "--capture", path], timeZone: zone)
    XCTAssertFalse(result.usage)
    XCTAssertEqual(result.exitCode, 1)
    XCTAssertTrue(result.line.hasPrefix("FAIL"))
  }

  func testMismatchLinesBeforeTheCaptureAreCounted() throws {
    let part = "display=2 scene=desktop part=key px=0,0,20,70 alpha=1 level=26 window=7 mask=none listed=none"
    let mismatch = part + " MISMATCH"
    let capture = try image { _, row in row < 70 ? black : background }
    let lines = [record(mismatch, at: "00:59:59.999"), record(summary()), record(mismatch, at: instant),
                 record(mismatch, at: "01:00:00.251"),
                 record(mismatch.replacingOccurrences(of: "display=2", with: "display=3")), record(part)]
    let result = BarCheck.run(arguments: try arguments(capture, log: lines), timeZone: zone)
    XCTAssertEqual(result.exitCode, 0)
    XCTAssertTrue(result.line.hasSuffix("MISMATCH 2"))
  }

  func testLuminanceIsBT709OnTheStoredComponents() throws {
    let colors: [RGB] = [black, [255, 0, 0], [0, 255, 0], [0, 0, 255], [128, 128, 128]]
    let capture = try image(width: 3, height: 5) { _, row in colors[row] }
    let values = BarCheck.rowMedians(capture, rows: 1..<5)
    XCTAssertEqual(values.map { Int(($0 * 1000).rounded()) }, [213, 715, 72, 502])
    XCTAssertEqual(BarCheck.blackLimit, 0.05)
    XCTAssertEqual(BarCheck.rowsBelow, 4)
  }
}
