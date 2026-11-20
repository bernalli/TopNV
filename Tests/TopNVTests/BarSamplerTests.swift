import AppKit
import os
import XCTest
import TopNVCore
@testable import TopNV

/// Records on which thread every window list read ran. The reads can run on any thread.
private final class ReadLog: Sendable {
  private let threads = OSAllocatedUnfairLock(initialState: [Bool]())

  func record() -> Int {
    threads.withLock { recorded in
      recorded.append(Thread.isMainThread)
      return recorded.count
    }
  }

  var onMain: [Bool] { threads.withLock { $0 } }
}

@MainActor
final class BarSamplerTests: XCTestCase {
  private let menu = MenuBarEvidence.Window(owner: .windowServer, layer: 24,
                                            bounds: CGRect(x: 0, y: 949, width: 1512, height: 33))

  private func sampler(_ log: ReadLog, gate: DispatchSemaphore? = nil, signalTime: Double? = nil) -> BarSampler {
    let menu = menu
    return BarSampler(reader: { _ in
      // Bounded, so that a read on the main thread fails the test instead of hanging it.
      _ = gate?.wait(timeout: .now() + 1)
      let readCount = log.record()
      return WindowListRead(windows: [menu], signalTime: signalTime ?? Double(readCount), uptime: 7)
    })
  }

  func testATimerSampleReadsTheWindowListOffTheMainThreadAndKeepsItsAcquisitionTime() {
    _ = NSApplication.shared
    let log = ReadLog()
    let sampler = sampler(log, signalTime: 42)
    let delivered = expectation(description: "sample delivered")
    var samples: [BarSample] = []
    var deliveredOnMain = false
    sampler.onSample = {
      deliveredOnMain = Thread.isMainThread
      samples.append(sampler.sampleNow())
      delivered.fulfill()
    }
    sampler.requestSample()
    wait(for: [delivered], timeout: 2)
    XCTAssertEqual(log.onMain, [false])
    XCTAssertTrue(deliveredOnMain)
    XCTAssertEqual(samples.first?.signalTime, 42)
    XCTAssertEqual(samples.first?.now, 7)
    XCTAssertEqual(samples.first?.windows?.count, 1)
  }

  func testRequestsDuringOneReadAreCoalescedIntoOneRecoveryRead() {
    _ = NSApplication.shared
    let log = ReadLog()
    let gate = DispatchSemaphore(value: 0)
    let sampler = sampler(log, gate: gate)
    let delivered = expectation(description: "original and recovery samples delivered")
    delivered.expectedFulfillmentCount = 2
    var count = 0
    sampler.onSample = {
      count += 1
      _ = sampler.sampleNow()
      delivered.fulfill()
    }
    sampler.requestSample()
    sampler.requestSample()
    sampler.requestSample()
    XCTAssertEqual(count, 0, "A request never blocks the main thread on the read")
    gate.signal()
    gate.signal()
    wait(for: [delivered], timeout: 2)
    XCTAssertEqual(count, 2)
    XCTAssertEqual(log.onMain, [false, false])
  }

  func testAReadThatStartedBeforeASpaceOrScreenEventIsDiscarded() {
    _ = NSApplication.shared
    let log = ReadLog()
    let gate = DispatchSemaphore(value: 0)
    let sampler = sampler(log, gate: gate)
    var count = 0
    sampler.onSample = {
      count += 1
      _ = sampler.sampleNow()
    }
    sampler.requestSample()
    sampler.discardPending()
    gate.signal()
    let read = expectation(description: "stale read finished")
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { read.fulfill() }
    wait(for: [read], timeout: 2)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    XCTAssertEqual(count, 0)
    XCTAssertEqual(log.onMain, [false])

    // The next request reads again and is delivered.
    let delivered = expectation(description: "fresh sample delivered")
    sampler.onSample = {
      count += 1
      _ = sampler.sampleNow()
      delivered.fulfill()
    }
    gate.signal()
    sampler.requestSample()
    wait(for: [delivered], timeout: 2)
    XCTAssertEqual(count, 1)
  }

  func testASampleWithoutADeliveredReadReadsSynchronously() {
    _ = NSApplication.shared
    let log = ReadLog()
    let sampler = sampler(log, signalTime: 5)
    let sample = sampler.sampleNow()
    XCTAssertEqual(sample.signalTime, 5)
    XCTAssertEqual(log.onMain, [true])
  }

  func testTheControllerDiscardsPendingReadsOnEverySystemEvent() throws {
    let recorder = DiscardRecorder()
    let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
    let controller = OverlayController(
      settings: AppSettings(defaults: defaults), displays: { [] }, sampler: recorder,
      bands: NoParts(), edges: NoParts(), corners: NoParts(), keys: NoKeys(),
      makeClock: { _ in NoClock() }, orderFront: { _ in }, scheduleRebuild: { _, _ in },
      testCopy: true, registryLine: { _ in })
    controller.systemChanged(.space, uptime: 1)
    XCTAssertEqual(recorder.events, ["discard", "sample"])
    recorder.events.removeAll()
    controller.systemChanged(.screen, uptime: 2)
    XCTAssertEqual(recorder.events.first, "discard")
  }
}

@MainActor
private final class DiscardRecorder: BarSampling {
  var onSample: (() -> Void)?
  var events: [String] = []
  func sampleNow() -> BarSample {
    events.append("sample")
    return .init(displays: [], windows: [], systemFullScreen: false, appearance: [:], activeKeyWindows: [:],
                 now: 1, reduceMotion: true, signalTime: 1)
  }
  func monitorAppearance(_ enabled: Bool) {}
  func scheduleSamples(needed: Bool, duringReveal: Bool) {}
  func discardPending() { events.append("discard") }
}

@MainActor
final class NoParts: BarPartExecuting {
  func apply(_ plan: BarPlan) -> BarEntries { [:] }
  func closeAll() {}
}

@MainActor
final class NoKeys: BarKeyExecuting {
  func apply(_ plan: BarPlan) -> BarEntries { [:] }
  func closeAll() {}
  func activeWindowIDs(display: UInt32) -> [Int] { [] }
  func closeChanged(frames: [UInt32: CGRect], enabled: Bool, scales: [UInt32: CGFloat]) -> Set<UInt32> { [] }
}

@MainActor
private final class NoClock: EntranceTiming {
  func start(_ entrance: BarEntrance, returnSignal: Double?, onFrame: @escaping (Double) -> Void,
             onFinish: @escaping () -> Void) {}
  func surfaceEnded(at time: Double) {}
  func finishIfOverdue() {}
  func cancel() {}
}
