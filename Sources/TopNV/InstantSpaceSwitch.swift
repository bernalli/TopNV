import AppKit
import Carbon
import OSLog
import TopNVCore

private let signature: OSType = 0x544E5653 // TNVS

private let handleShortcut: EventHandlerUPP = { _, event, context in
  guard let event, let context else { return OSStatus(eventNotHandledErr) }
  var hotKey = EventHotKeyID()
  let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                 nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
  guard status == noErr, hotKey.signature == signature, hotKey.id == 1 || hotKey.id == 2 else {
    return OSStatus(eventNotHandledErr)
  }
  MainActor.assumeIsolated {
    let controller = Unmanaged<InstantSpaceSwitch>.fromOpaque(context).takeUnretainedValue()
    controller.move(hotKey.id == 1 ? .left : .right)
  }
  return noErr
}

@MainActor
final class InstantSpaceSwitch {
  private typealias Request = SpaceSwitchMeasurements.Request

  private static let log = Logger(subsystem: "TopNV", category: "InstantSpaceSwitch")
  private let sky: SkyLightSpaces
  private var registrations: [EventHotKeyRef] = []
  private var handler: EventHandlerRef?
  private var observation: NSObjectProtocol?
  private var measurements = SpaceSwitchMeasurements()

  init?() {
    do {
      sky = try SkyLightSpaces()
    } catch {
      Self.log.error("Shortcuts unavailable: \(String(describing: error), privacy: .public)")
      return nil
    }
    let target = GetApplicationEventTarget()
    var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let status = InstallEventHandler(target, handleShortcut, 1, &event, Unmanaged.passUnretained(self).toOpaque(),
                                     &handler)
    guard status == noErr else {
      Self.log.error("Shortcut handler unavailable: OSStatus=\(status)")
      return nil
    }
    for (index, key) in [kVK_LeftArrow, kVK_RightArrow].enumerated() {
      var registration: EventHotKeyRef?
      let hotKey = EventHotKeyID(signature: signature, id: UInt32(index + 1))
      let status = RegisterEventHotKey(
        UInt32(key), UInt32(controlKey | optionKey), hotKey, target, UInt32(kEventHotKeyExclusive), &registration)
      if status == noErr, let registration {
        registrations.append(registration)
      } else {
        Self.log.error("Shortcut unavailable: keyCode=\(key) OSStatus=\(status)")
      }
    }
    observation = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.receivedNotification(at: .now()) }
    }
  }

  func stop() {
    for registration in registrations { UnregisterEventHotKey(registration) }
    registrations.removeAll()
    if let handler { RemoveEventHandler(handler) }
    handler = nil
    if let observation { NSWorkspace.shared.notificationCenter.removeObserver(observation) }
    observation = nil
    let pending = measurements.drain()
    guard !pending.isEmpty else { return }
    let state = try? sky.snapshot()
    for request in pending { report(request, state: state, latency: "terminated", shared: false) }
  }

  fileprivate func move(_ direction: SpaceDirection) {
    do {
      let state = try sky.snapshot()
      guard let target = try state.neighbor(direction) else { return }
      let request = Request(display: state.mainUUID, origin: state.currentID, target: target, start: .now())
      measurements.record(request)
      sky.switchSpace(display: state.identifier, to: target)
      DispatchQueue.main.asyncAfter(deadline: request.deadline) { [weak self] in
        self?.expire(request.identifier)
      }
    } catch {
      Self.log.error("Shortcut ignored: \(String(describing: error), privacy: .public)")
    }
  }

  private func receivedNotification(at received: DispatchTime) {
    guard !measurements.isEmpty else { return }
    let state = try? sky.snapshot()
    let matched = measurements.observe(display: state?.mainUUID, current: state?.currentID, at: received)
    // Requests for the same destination can share one global observation.
    for request in matched {
      report(request, state: state, latency: milliseconds(from: request.start, to: received),
             shared: matched.count > 1)
    }
  }

  private func expire(_ identifier: UUID) {
    guard let request = measurements.expire(identifier) else { return }
    report(request, state: try? sky.snapshot(), latency: "timeout", shared: false)
  }

  private func milliseconds(from start: DispatchTime, to end: DispatchTime) -> String {
    let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    return String(format: "%.3f", elapsed)
  }

  private func report(_ request: Request, state: ManagedDisplaySpaces?, latency: String, shared: Bool) {
    let current = state.flatMap { $0.mainUUID == request.display ? $0.currentID : nil }
    let match = current.map { String($0 == request.target) } ?? "unknown"
    let observed = current.map(String.init) ?? "unknown"
    let result = "current=\(observed) match=\(match) shared=\(shared)"
    let route = "from=\(request.origin) to=\(request.target) notification_ms=\(latency)"
    let diagnostic = request.lastUnmatched.map { sample in
      let elapsed = milliseconds(from: request.start, to: sample.received)
      let current = sample.current.map(String.init) ?? "unknown"
      return " unmatched_ms=\(elapsed) unmatched_current=\(current)"
    } ?? ""
    Self.log.notice("\(route, privacy: .public) \(result, privacy: .public)\(diagnostic, privacy: .public)")
  }
}
