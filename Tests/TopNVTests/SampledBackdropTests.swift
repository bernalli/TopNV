import BackdropRuntime
import QuartzCore
import TopNVCore
import XCTest

@MainActor final class SampledBackdropTests: XCTestCase {
  private func makeBackdrop() throws -> CALayer {
    var reason: NSString?
    return try XCTUnwrap(LuminanceKey.normal.matrix.withUnsafeBufferPointer {
      KOCreateBackdrop($0.baseAddress!, $0.count, CGRect(x: 0, y: 0, width: 100, height: 30), 1, &reason)
    })
  }

  /// A plain layer stores and returns the two luma keys, but the render server never samples it.
  func testALayerWithoutTheLumaPropertiesIsNotObserved() throws {
    let plain = CALayer()
    plain.filters = try makeBackdrop().filters
    XCTAssertNil(KOSampledBackdrop.observe(plain) { _, _ in })
    XCTAssertNil(plain.delegate)
    XCTAssertNil(plain.value(forKey: "tracksLuma"))
    XCTAssertEqual(plain.filters?.count, 1)
  }

  func testASecondObserverAndAMalformedMatrixLeaveTheFirstObserverAndTheFilterUntouched() throws {
    let layer = try makeBackdrop()
    let ordinary = try XCTUnwrap(layer.filters?.first as? NSObject)
    guard let source = KOSampledBackdrop.observe(layer, sample: { _, _ in }) else {
      throw XCTSkip("Sampled backdrops unavailable on this system")
    }
    XCTAssertNil(KOSampledBackdrop.observe(layer) { _, _ in })
    XCTAssertTrue(layer.delegate === source)
    for count in [0, 19, 21] {
      let values = [Float](repeating: 0.5, count: max(count, 1))
      XCTAssertFalse(values.withUnsafeBufferPointer { source.applyMatrix($0.baseAddress, count: count) }, "\(count)")
      XCTAssertTrue(layer.filters?.first as? NSObject === ordinary, "\(count)")
    }
    XCTAssertTrue(source.stopTracking())
    XCTAssertNil(layer.delegate)
    XCTAssertEqual(layer.value(forKey: "tracksLuma") as? Bool, false)
    XCTAssertTrue(layer.filters?.first as? NSObject === ordinary)
  }
}
