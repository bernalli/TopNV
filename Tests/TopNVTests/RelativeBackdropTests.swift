import BackdropRuntime
import QuartzCore
import TopNVCore
import XCTest

@testable import TopNV

@MainActor final class RelativeBackdropTests: XCTestCase {
  private final class Lines {
    var all: [String] = []
  }

  func testOrdinaryKeyIsTheStartupFilterEvenAfterAValidSample() async throws {
    let key = RelativeMenuBarKey(isTestCopy: true)
    XCTAssertFalse(key.enabled)
    let layer = try makeLayer()
    let original = try XCTUnwrap(layer.filters?.first as? NSObject)
    key.observe(layer)
    (layer.delegate as? KOSampledBackdrop)?.backdropLayer(layer, didChangeLuma: 0.12)
    await drainSamples()
    XCTAssertTrue(layer.filters?.first as? NSObject === original)
  }

  func testProductionMakesNoSamplingCallKeepsTheOrdinaryFilterAndLogsNothing() throws {
    let lines = Lines()
    let key = RelativeMenuBarKey(isTestCopy: false) { lines.all.append($0) }
    let layer = try makeLayer()
    let ordinary = try XCTUnwrap(layer.filters?.first as? NSObject)
    key.observe(layer)
    key.toggle()
    key.toggleLamp()
    XCTAssertFalse(key.lampEnabled)
    XCTAssertFalse(key.available)
    XCTAssertFalse(key.enabled)
    XCTAssertNil(layer.delegate)
    XCTAssertEqual(layer.value(forKey: "tracksLuma") as? Bool, false)
    XCTAssertTrue(layer.filters?.first as? NSObject === ordinary)
    XCTAssertEqual(matrix(layer), LuminanceKey.normal.matrix)
    XCTAssertEqual(lines.all, [])
  }

  func testATestCopyLogsAvailabilityEachVisibleSampleChangeAndTheSwitch() async throws {
    let lines = Lines()
    let key = RelativeMenuBarKey(isTestCopy: true) { lines.all.append($0) }
    XCTAssertEqual(lines.all, ["Relative key available=\(key.available)"])
    guard key.available else { throw XCTSkip("Sampled backdrops unavailable on this system") }
    let layer = try makeLayer()
    key.observe(layer)
    let reader = try XCTUnwrap(layer.delegate as? KOSampledBackdrop)
    // 0.121 is the same visible step as 0.12; a protected sample is not a number.
    for luma in [0.12, 0.121, 0.5, 0.12, .nan] {
      reader.backdropLayer(layer, didChangeLuma: luma)
      await drainSamples()
    }
    XCTAssertEqual(Array(lines.all.dropFirst()), [
      "Sample 0.120 over 100 pt, enabled=false, relative key white to 0.024, black from 0.112",
      "Sample 0.500 over 100 pt, enabled=false, relative key white to 0.100, black from 0.465",
      "Sample 0.120 over 100 pt, enabled=false, relative key white to 0.024, black from 0.112",
      "Sample nan over 100 pt, enabled=false, relative key white to 0.043, black from 0.377"
    ])
    key.toggle()
    key.toggle()
    XCTAssertEqual(Array(lines.all.suffix(2)), ["Relative key enabled=true", "Relative key enabled=false"])
  }

  func testARefusedBackdropLogsWhyTheRelativeKeyIsOff() throws {
    let lines = Lines()
    let key = RelativeMenuBarKey(isTestCopy: true) { lines.all.append($0) }
    guard key.available else { throw XCTSkip("Sampled backdrops unavailable on this system") }
    key.observe(CALayer())
    XCTAssertFalse(key.available)
    XCTAssertEqual(lines.all.last, "Relative key off for this session: a backdrop refused the sampling setup")
  }

  func testLiveBackdropsUseTheirOwnSampleAndRestoreTheOriginalFilter() async throws {
    let key = RelativeMenuBarKey(isTestCopy: true)
    guard key.available else { throw XCTSkip("Sampled backdrops unavailable on this system") }
    key.toggle()
    let left = try makeLayer()
    let right = try makeLayer()
    let ordinary = try XCTUnwrap(left.filters?.first as? NSObject)
    let other = try XCTUnwrap(right.filters?.first as? NSObject)
    key.observe(left)
    key.observe(right)
    let reader = try XCTUnwrap(left.delegate as? KOSampledBackdrop)
    XCTAssertTrue(left.filters?.first as? NSObject === ordinary)

    reader.backdropLayer(left, didChangeLuma: 0.75)
    await drainSamples()
    XCTAssertEqual(matrix(left), LuminanceKey.forBackdrop(backgroundLuma: 0.75, relativeEnabled: true).matrix)
    XCTAssertTrue(right.filters?.first as? NSObject === other)

    key.toggle()
    XCTAssertTrue(left.filters?.first as? NSObject === ordinary)
    key.toggle()
    XCTAssertEqual(matrix(left), LuminanceKey.forBackdrop(backgroundLuma: 0.75, relativeEnabled: true).matrix)

    reader.backdropLayer(left, didSampleProtectedLuma: true)
    await drainSamples()
    XCTAssertTrue(left.filters?.first as? NSObject === ordinary)
  }

  func testLampUsesSampleIndependentlyOfTheRelativeKeySwitch() async throws {
    let key = RelativeMenuBarKey(isTestCopy: true)
    XCTAssertFalse(key.lampEnabled)
    guard key.available else { throw XCTSkip("Sampled backdrops unavailable on this system") }
    let layer = try makeLayer()
    key.observe(layer)
    let reader = try XCTUnwrap(layer.delegate as? KOSampledBackdrop)
    key.toggleLamp()
    XCTAssertFalse(key.enabled)
    XCTAssertEqual(matrix(layer), LuminanceKey.normal.matrix)
    reader.backdropLayer(layer, didChangeLuma: 0.875)
    await drainSamples()
    let relative = LuminanceKey.forBackdrop(backgroundLuma: 0.875, relativeEnabled: true).matrix
    XCTAssertEqual(matrix(layer), relative)
    key.toggleLamp()
    XCTAssertEqual(matrix(layer), LuminanceKey.normal.matrix)
    key.toggle()
    key.toggleLamp()
    key.toggleLamp()
    XCTAssertTrue(key.enabled)
    XCTAssertEqual(matrix(layer), relative)
    key.toggleLamp()
    key.toggle()
    reader.backdropLayer(layer, didSampleProtectedLuma: true)
    await drainSamples()
    XCTAssertEqual(matrix(layer), LuminanceKey.normal.matrix)
  }

  private func makeLayer() throws -> CALayer {
    var reason: NSString?
    return try XCTUnwrap(LuminanceKey.normal.matrix.withUnsafeBufferPointer {
      KOCreateBackdrop($0.baseAddress!, $0.count, CGRect(x: 0, y: 0, width: 100, height: 30), 1, &reason)
    })
  }

  private func matrix(_ layer: CALayer) -> [Float] {
    guard let filter = layer.filters?.first as? NSObject,
          let value = filter.value(forKey: "inputColorMatrix") as? NSValue else { return [] }
    var floats = [Float](repeating: 0, count: 20)
    floats.withUnsafeMutableBytes { value.getValue($0.baseAddress!, size: $0.count) }
    return floats
  }

  private func drainSamples() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }
}
