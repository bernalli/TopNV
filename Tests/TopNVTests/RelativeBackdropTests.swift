import BackdropRuntime
import QuartzCore
import TopNVCore
import XCTest

@testable import TopNV

@MainActor final class RelativeBackdropTests: XCTestCase {
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

  func testProductionDoesNotObserveOrEnableTheExperiment() throws {
    let key = RelativeMenuBarKey(isTestCopy: false)
    let layer = try makeLayer()
    key.observe(layer)
    key.toggle()
    XCTAssertFalse(key.available)
    XCTAssertFalse(key.enabled)
    XCTAssertNil(layer.delegate)
    XCTAssertEqual(matrix(layer), LuminanceKey.normal.matrix)
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
