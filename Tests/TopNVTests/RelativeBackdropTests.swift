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
    key.observe(layer, display: 1)
    (layer.delegate as? KOSampledBackdrop)?.backdropLayer(layer, didChangeLuma: 0.12)
    await drainSamples()
    XCTAssertTrue(layer.filters?.first as? NSObject === original)
  }

  func testProductionMakesNoSamplingCallKeepsTheOrdinaryFilterAndLogsNothing() throws {
    let lines = Lines()
    let key = RelativeMenuBarKey(isTestCopy: false, log: { lines.all.append($0) })
    let layer = try makeLayer()
    let ordinary = try XCTUnwrap(layer.filters?.first as? NSObject)
    key.observe(layer, display: 1)
    key.toggle()
    key.toggleLamp()
    key.selectLampKey(LampKeyPreset.choices[4])
    key.selectLampPlate(LampPlatePreset.choices[4], present: { XCTFail("Production presented a plate") })
    XCTAssertEqual(key.lampPlate.command, .lampPlate1)
    XCTAssertEqual(key.lampKey.command, .lampKey2)
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
    let key = RelativeMenuBarKey(isTestCopy: true, log: { lines.all.append($0) })
    XCTAssertEqual(lines.all, ["Relative key available=\(key.available)"])
    guard key.available else { throw XCTSkip("Sampled backdrops unavailable on this system") }
    let layer = try makeLayer()
    key.observe(layer, display: 1)
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
    let key = RelativeMenuBarKey(isTestCopy: true, log: { lines.all.append($0) })
    guard key.available else { throw XCTSkip("Sampled backdrops unavailable on this system") }
    key.observe(CALayer(), display: 1)
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
    key.observe(left, display: 1)
    key.observe(right, display: 2)
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

  func testFixedLampKeySurvivesQueuedAndProtectedSamplesAndRestoresRelativeKey() async throws {
    let key = RelativeMenuBarKey(isTestCopy: true)
    guard key.available else { throw XCTSkip("Sampled backdrops unavailable on this system") }
    let layer = try makeLayer()
    key.observe(layer, display: 1)
    let reader = try XCTUnwrap(layer.delegate as? KOSampledBackdrop)
    key.toggle()
    reader.backdropLayer(layer, didChangeLuma: 0.75)
    key.toggleLamp()
    let fixed = LampKeyPreset.choices[1].key.matrix
    XCTAssertEqual(matrix(layer), fixed)
    await drainSamples()
    XCTAssertEqual(matrix(layer), fixed)
    key.toggleLampOnly()
    XCTAssertEqual(matrix(layer), LuminanceKey.forBackdrop(backgroundLuma: 0.75, relativeEnabled: true).matrix)
    key.toggleLamp()
    reader.backdropLayer(layer, didSampleProtectedLuma: true)
    await drainSamples()
    XCTAssertEqual(matrix(layer), fixed)
    key.toggleLamp()
    XCTAssertEqual(matrix(layer), LuminanceKey.normal.matrix)
  }

  func testChangingLampKeyImmediatelyUpdatesAllLitBackdropsAndNewWindows() throws {
    let lines = Lines()
    let key = RelativeMenuBarKey(isTestCopy: true, log: { lines.all.append($0) })
    guard key.available else { throw XCTSkip("Sampled backdrops unavailable on this system") }
    let left = try makeLayer()
    let right = try makeLayer()
    key.observe(left, display: 1)
    key.observe(right, display: 2)
    key.toggleLamp()
    XCTAssertEqual(matrix(left), LampKeyPreset.choices[1].key.matrix)
    let fifth = LampKeyPreset.choices[4]
    key.selectLampKey(fifth)
    XCTAssertEqual(matrix(left), fifth.key.matrix)
    XCTAssertEqual(matrix(right), fifth.key.matrix)
    XCTAssertEqual(lines.all.filter { $0.hasPrefix("LampKey ") }, ["LampKey voce=5 black=0.95 white=0.45"])
    let next = try makeLayer()
    key.observe(next, display: 1)
    XCTAssertEqual(matrix(next), fifth.key.matrix)
    key.toggleLamp()
    for layer in [left, right, next] { XCTAssertEqual(matrix(layer), LuminanceKey.normal.matrix) }
  }

  func testFixedLampKeyFollowsEachDisplayIgnitionWithoutACallback() throws {
    var lit: Set<UInt32> = [2]
    let key = RelativeMenuBarKey(isTestCopy: true, isLampLit: { lit.contains($0) })
    guard key.available else { throw XCTSkip("Sampled backdrops unavailable on this system") }
    let left = try makeLayer()
    let right = try makeLayer()
    key.observe(left, display: 1)
    key.observe(right, display: 2)
    let first = LampKeyPreset.choices[0]
    key.selectLampKey(first)
    XCTAssertEqual(matrix(right), LuminanceKey.normal.matrix)
    key.toggleLamp()
    XCTAssertEqual(matrix(left), LuminanceKey.normal.matrix)
    XCTAssertEqual(matrix(right), first.key.matrix)
    lit.insert(1)
    key.lampChanged(on: 1)
    XCTAssertEqual(matrix(left), first.key.matrix)
    key.toggle()
    key.sample(0.5, for: left, at: 10)
    lit.remove(1)
    key.lampChanged(on: 1)
    XCTAssertEqual(matrix(left), LuminanceKey.forBackdrop(backgroundLuma: 0.5, relativeEnabled: true).matrix)
    XCTAssertEqual(matrix(right), first.key.matrix)
  }

  func testProbeReportsEachIntervalIncludingEqualSamplesAndTimeouts() throws {
    var now = 10.0
    var timers: [Timer] = []
    let clock = ProbeClock(now: { now }, schedule: { interval, action in
      let timer = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { action() } }
      timers.append(timer)
      return timer
    })
    let lines = Lines()
    let key = RelativeMenuBarKey(isTestCopy: true, clock: clock, log: { lines.all.append($0) })
    guard key.available else { throw XCTSkip("Sampled backdrops unavailable on this system") }
    let layer = try makeLayer()
    key.observe(layer, display: 9)
    XCTAssertTrue(timers.isEmpty)
    key.toggleLampOnly()
    let timer = try XCTUnwrap(timers.first)
    XCTAssertEqual(timer.timeInterval, 1)
    for _ in 0..<2 {
      key.sample(0.5, for: layer, at: now + 0.25)
      now += 1
      timer.fire()
    }
    now += 1
    timer.fire()
    let prefix = "Probe display=9 luma="
    let suffix = " key=normal white=0.043 black=0.377"
    let sample = prefix + "0.500 forced=true lastCallbackAge=0.750" + suffix
    XCTAssertEqual(lines.all.filter { $0.hasPrefix(prefix) }, [
      sample, sample, prefix + "none forced=true lastCallbackAge=1.750" + suffix
    ])
    key.toggleLamp()
    XCTAssertEqual(timers.count, 1)
    now += 1
    timer.fire()
    let fixed = prefix + "none forced=true lastCallbackAge=2.750 key=fixed white=0.300 black=0.940"
    XCTAssertEqual(lines.all.last, fixed)
    key.toggleLamp()
    XCTAssertFalse(timer.isValid)
    key.toggle()
    XCTAssertEqual(timers.count, 2)
    key.toggle()
    XCTAssertFalse(try XCTUnwrap(timers.last).isValid)
    let production = RelativeMenuBarKey(isTestCopy: false, clock: clock)
    production.observe(layer, display: 9)
    production.toggleLampOnly()
    production.toggleLamp()
    production.toggle()
    XCTAssertEqual(timers.count, 2)
  }

  func testProbeTimeoutExcludesLateCallbacksAndFailedRequests() {
    var probe = BackdropProbe(display: 3)
    let prefix = "Probe display=3 luma=none "
    let suffix = "lastCallbackAge=0.125 key=normal white=0.043 black=0.377"
    probe.begin(at: 2, forced: true)
    probe.receive(0.875, at: 3.125)
    XCTAssertEqual(probe.line(at: 3.25, key: .normal), prefix + "forced=true " + suffix)
    probe.begin(at: 4, forced: false)
    probe.receive(0.875, at: 4.875)
    XCTAssertEqual(probe.line(at: 5, key: .normal), prefix + "forced=false " + suffix)
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
