import BackdropRuntime
import QuartzCore
import XCTest

final class BackdropRuntimeInputTests: XCTestCase {
  @MainActor
  func testMalformedCurveBuffersFailBeforeFilterLookup() {
    let matrix = [Float](repeating: 0, count: 20)

    func check(_ controls: [Double]?, count: Int, reasonContains text: String) {
      matrix.withUnsafeBufferPointer { matrix in
        func call(_ pointer: UnsafePointer<Double>?) {
          var reason: NSString?
          let layer = KOCreateBackdrop(matrix.baseAddress!, matrix.count, pointer, count,
                                       .zero, 1, &reason)
          XCTAssertNil(layer)
          XCTAssertTrue((reason as String?)?.contains(text) == true)
        }
        if let controls {
          controls.withUnsafeBufferPointer { call($0.baseAddress) }
        } else {
          call(nil)
        }
      }
    }

    for count in 1...8 {
      check(nil, count: count, reasonContains: "four controls")
    }
    for count in 0...8 where count != 4 {
      check(Array(repeating: 0, count: 8), count: count, reasonContains: "four controls")
    }
    for index in 0..<4 {
      for bad in [Double.nan, .infinity, -.infinity, -0.01, 1.01] {
        var values = [0.0, 0.5, 1.0, 1.0]
        values[index] = bad
        check(values, count: 4, reasonContains: "finite and in 0...1")
      }
    }
  }
}
