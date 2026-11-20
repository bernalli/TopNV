import AppKit
import os
import XCTest
import TopNVCore
@testable import TopNV

private struct PlannedRead: Sendable {
  let sample: WindowListRead
  var started: XCTestExpectation?
  var release: DispatchSemaphore?
}

private final class PlannedReads: Sendable {
  private let steps = OSAllocatedUnfairLock(initialState: [PlannedRead]())

  func enqueue(_ step: PlannedRead) { steps.withLock { $0.append(step) } }

  func read() -> WindowListRead {
    let step = steps.withLock { $0.isEmpty ? nil : $0.removeFirst() }
    guard let step else {
      XCTFail("Unexpected window list read")
      return WindowListRead(windows: nil, signalTime: 0, uptime: 0)
    }
    if step.release != nil { XCTAssertFalse(Thread.isMainThread) }
    step.started?.fulfill()
    if let release = step.release {
      XCTAssertEqual(release.wait(timeout: .now() + 2), .success)
    }
    return step.sample
  }
}

@MainActor
private final class SamplingFixture {
  let bands = Parts([.band])
  let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
  let display = BarDisplay(
    id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
    safeAreaTop: 32, scale: 2, notchWidth: 180, isBuiltin: true)
  var clocks: [Clock] = []
  var delayed: [DispatchWorkItem] = []
  let reads = PlannedReads()
  var timer: Timer?
  var appliedTimes: [Double] = []
  var onApplySample: ((Double) -> Void)?
  lazy var sampler = BarSampler(
    reader: { [reads] _ in reads.read() },
    makeSample: { [unowned self] read in
      self.appliedTimes.append(read.signalTime)
      self.onApplySample?(read.signalTime)
      return BarSample(displays: [self.display], windows: read.windows,
                       systemFullScreen: false, appearance: [1: .light], activeKeyWindows: [:],
                       now: read.uptime, reduceMotion: false, signalTime: read.signalTime)
    },
    installTimer: { [unowned self] in self.timer = $0 })

  lazy var controller = OverlayController(
    settings: settings, displays: { [unowned self] in [self.display] }, sampler: sampler,
    bands: bands, edges: NoParts(), corners: NoParts(), keys: NoKeys(),
    makeClock: { [unowned self] _ in
      let clock = Clock()
      self.clocks.append(clock)
      return clock
    },
    orderFront: { _ in }, scheduleRebuild: { [unowned self] _, work in self.delayed.append(work) },
    testCopy: true, registryLine: { _ in })

  func enqueue(_ time: Double, layer: Int? = nil, alpha: Double = 1, started: XCTestExpectation? = nil,
               release: DispatchSemaphore? = nil) {
    let menu = MenuBarEvidence.Window(owner: .windowServer, layer: 24,
                                      bounds: CGRect(x: 0, y: 949, width: 1512, height: 33))
    var windows = [menu]
    if let layer {
      windows.append(.init(owner: .desktop, layer: layer, bounds: display.frame,
                           isWindowManager: true, alpha: alpha, number: 99))
    }
    reads.enqueue(.init(sample: WindowListRead(windows: windows, signalTime: time, uptime: time),
                        started: started, release: release))
  }

  func start() {
    enqueue(1)
    controller.systemChanged(.screen, uptime: 0)
    delayed.removeLast().perform()
  }

  func tick() { timer?.fire() }
}

@MainActor
final class OverlaySamplingTests: XCTestCase {
  func testSynchronousRebuildsRejectReadsFromAnEarlierGeneration() {
    enum Rebuild: CaseIterable { case settings, space, screen }
    for rebuild in Rebuild.allCases {
      let fixture = SamplingFixture()
      fixture.start()
      let controller = fixture.controller
      if rebuild == .screen { controller.systemChanged(.screen, uptime: 1.5) }

      let started = expectation(description: "\(rebuild) stale read started")
      let release = DispatchSemaphore(value: 0)
      fixture.enqueue(3.5, layer: 19, started: started, release: release)
      fixture.tick()
      wait(for: [started], timeout: 2)

      fixture.enqueue(3)
      switch rebuild {
      case .settings: controller.settingsChanged()
      case .space: controller.systemChanged(.space, uptime: 2.5)
      case .screen: fixture.delayed.last?.perform()
      }
      XCTAssertEqual(fixture.appliedTimes, [1, 3], "\(rebuild) applies its sample synchronously")

      let recovered = expectation(description: "\(rebuild) recovery applied")
      fixture.onApplySample = { if $0 == 4 { recovered.fulfill() } }
      fixture.enqueue(4)
      fixture.tick()
      release.signal()
      wait(for: [recovered], timeout: 2)
      XCTAssertEqual(fixture.appliedTimes, [1, 3, 4])
      XCTAssertFalse(fixture.bands.plans.contains { $0.displays[1]?.kind == .overview })
    }
  }

  func testScreenNotificationRejectsAReadEvenBeforeItsRebuild() {
    let fixture = SamplingFixture()
    fixture.start()
    let started = expectation(description: "pre-notification read started")
    let release = DispatchSemaphore(value: 0)
    fixture.enqueue(2, layer: 19, started: started, release: release)
    fixture.tick()
    wait(for: [started], timeout: 2)

    fixture.controller.systemChanged(.screen, uptime: 2.5)
    let recovered = expectation(description: "post-notification read applied")
    fixture.onApplySample = { if $0 == 3 { recovered.fulfill() } }
    fixture.enqueue(3)
    fixture.tick()
    release.signal()
    wait(for: [recovered], timeout: 2)
    XCTAssertEqual(fixture.appliedTimes, [1, 3])
    XCTAssertEqual(fixture.delayed.count, 1)
  }

  func testAnOlderOrEqualAcquisitionInTheCurrentGenerationIsDiscarded() {
    for (time, previousAsync) in [(1.0, false), (2.0, false), (1.0, true), (2.0, true)] {
      let fixture = SamplingFixture()
      fixture.start()
      fixture.enqueue(2)
      if previousAsync {
        let applied = expectation(description: "previous async read applied")
        fixture.onApplySample = { if $0 == 2 { applied.fulfill() } }
        fixture.tick()
        wait(for: [applied], timeout: 2)
      } else {
        fixture.controller.sample()
      }
      let started = expectation(description: "read with old acquisition time started")
      let release = DispatchSemaphore(value: 0)
      fixture.enqueue(time, layer: 19, started: started, release: release)
      fixture.tick()
      wait(for: [started], timeout: 2)
      let recovered = expectation(description: "newer read applied")
      fixture.onApplySample = { if $0 == 3 { recovered.fulfill() } }
      fixture.enqueue(3)
      fixture.tick()
      release.signal()
      wait(for: [recovered], timeout: 2)
      XCTAssertEqual(fixture.appliedTimes, [1, 2, 3])
    }
  }

  func testCoalescedTickDeliversTheOnlySurfaceEndToTheController() throws {
    let fixture = SamplingFixture()
    fixture.start()
    fixture.enqueue(2, layer: 19)
    fixture.controller.sample()
    let started = expectation(description: "return read started")
    let release = DispatchSemaphore(value: 0)
    fixture.enqueue(3, layer: 19, alpha: 0.8, started: started, release: release)
    fixture.tick()
    wait(for: [started], timeout: 2)

    let ended = expectation(description: "recovery read applied")
    fixture.onApplySample = { if $0 == 4 { ended.fulfill() } }
    fixture.enqueue(4)
    fixture.tick()
    fixture.tick()
    release.signal()
    wait(for: [ended], timeout: 2)
    XCTAssertEqual(fixture.appliedTimes, [1, 2, 3, 4])
    XCTAssertEqual(try XCTUnwrap(fixture.clocks.last).ends, [4])
  }

  func testStoppingSamplingClearsBothTheInFlightAndRecoveryRequests() {
    let fixture = SamplingFixture()
    fixture.start()
    let started = expectation(description: "read started before stop")
    let release = DispatchSemaphore(value: 0)
    fixture.enqueue(2, layer: 19, started: started, release: release)
    fixture.tick()
    wait(for: [started], timeout: 2)

    let unwanted = expectation(description: "no recovery read after stop")
    unwanted.isInverted = true
    fixture.tick()
    fixture.settings.hideNotch = false
    fixture.settings.roundCorners = false
    fixture.enqueue(3)
    // The settings rebuild itself is synchronous. It consumes the next planned read before stopping.
    fixture.controller.settingsChanged()
    fixture.enqueue(4, started: unwanted)
    release.signal()
    wait(for: [unwanted], timeout: 0.2)
    XCTAssertEqual(fixture.appliedTimes, [1, 3])
    XCTAssertEqual(fixture.timer?.isValid, false)
  }
}
