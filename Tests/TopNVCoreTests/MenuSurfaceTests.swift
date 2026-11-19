import XCTest
@testable import TopNVCore

final class MenuSurfaceTests: XCTestCase {
  private let strip = CGRect(x: 0, y: 948, width: 1512, height: 34)

  func testUsesAnotherLayerWhenThePreferredLayerDoesNotMatch() {
    let actual = MenuBarEvidence.Window(owner: .windowServer, layer: 25, bounds: strip)
    let offDisplay = MenuBarEvidence.Window(owner: .windowServer, layer: 24,
                                            bounds: strip.offsetBy(dx: strip.width, dy: 0))
    let surface = MenuBarEvidence.menuSurface(in: [offDisplay, actual], bandFrame: strip, preferredLayer: 24)
    XCTAssertEqual(surface?.layer, 25)
  }

  func testPrefersTheKnownLayerWhenBothSurfacesMatch() {
    let other = MenuBarEvidence.Window(owner: .windowServer, layer: 25, bounds: strip)
    let known = MenuBarEvidence.Window(owner: .windowServer, layer: 24, bounds: strip)
    let surface = MenuBarEvidence.menuSurface(in: [other, known], bandFrame: strip, preferredLayer: 24)
    XCTAssertEqual(surface?.layer, 24)
  }
}
