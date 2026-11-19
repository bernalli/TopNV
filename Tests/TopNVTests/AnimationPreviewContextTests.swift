import CoreGraphics
import TopNVCore
import XCTest

@testable import TopNV

@MainActor
final class AnimationPreviewContextTests: XCTestCase {
  func testOnlyAnInterruptedDisplayInvalidatesThePreviewSynchronously() {
    let controller = KeyedOverlayController(calibration: KeyCalibration.initial(bundleIdentifier: "test.copy"))
    var invalidated: [UInt32] = []
    controller.onPreviewInvalidated = { invalidated.append($0) }

    let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let visible = CGRect(x: 0, y: 0, width: 1200, height: 770)
    let band = CGRect(x: 0, y: 770, width: 1200, height: 30)
    let menu = MenuBarEvidence.Window(owner: .windowServer, layer: 24, bounds: band)

    func sample(_ windows: [MenuBarEvidence.Window], on displayID: UInt32) {
      let evidence = MenuBarEvidence.evaluate(frame: screen, visibleFrame: visible,
                                              bandFrame: band, windows: windows)
      var state = KeyedOverlayState()
      let decision = state.update(.init(activeWindowIDs: [], appearance: .unknown, context: evidence.context,
                                        menuVisible: evidence.menuVisible, enabled: true, now: 0))
      controller.invalidatePreviewIfNeeded(on: displayID, evidence: evidence, decision: decision)
    }

    sample([menu], on: 1)
    sample([menu], on: 2)
    XCTAssertTrue(invalidated.isEmpty)

    let reveal = MenuBarEvidence.Window(owner: .desktop, layer: 18, bounds: screen, isWindowManager: true)
    sample([menu, reveal], on: 2)
    XCTAssertEqual(invalidated, [2])

    let slide = MenuBarEvidence.Window(owner: .desktop, layer: -1,
                                       bounds: screen.offsetBy(dx: 30, dy: 0), isWindowManager: true)
    sample([menu, slide], on: 1)
    XCTAssertEqual(invalidated, [2, 1])

    let fullScreen = MenuBarEvidence.Window(owner: .application, layer: 0, bounds: screen)
    sample([menu, fullScreen], on: 3)
    XCTAssertEqual(invalidated, [2, 1, 3])

    sample([], on: 3)
    XCTAssertEqual(invalidated, [2, 1, 3, 3])
  }
}
