import Foundation

/// Orders appearance requests independently of AppKit and the private client.
public struct SystemDarkMenuBarState: Sendable {
  public struct Request: Hashable, Sendable {
    public let id: Int
    public let enabled: Bool
  }

  public enum Effect: Equatable, Sendable {
    case send(Request)
    case clearMarker
    case finishQuit(Bool)
  }

  public enum Reply: Sendable {
    case applied
    case uncertain
    case notSent
  }

  private enum Phase {
    case off, enabling, enableTimedOut, active, restoring, needsRestore
  }

  private var phase: Phase
  private var sequence = 0
  private var enableRequest: Request?
  private var latestRestore: Request?
  private var pendingRestores: Set<Request> = []
  private var quitting = false
  private var resumeKeyDuringRestore = false

  public init?(bundleIdentifier: String?, saved: Any?) {
    guard KeyCalibration.initial(bundleIdentifier: bundleIdentifier) != nil else { return nil }
    if let flag = saved as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID(), !flag.boolValue {
      phase = .off
    } else {
      phase = saved == nil ? .off : .needsRestore
    }
  }

  public var needsRestore: Bool { phase != .off }
  public var suspendsKey: Bool { needsRestore && !resumeKeyDuringRestore }

  private var canToggle: Bool {
    guard !quitting else { return false }
    switch phase {
    case .off: return pendingRestores.isEmpty
    case .active, .needsRestore: return true
    case .enabling, .enableTimedOut, .restoring: return false
    }
  }

  public func menuRow(clientAvailable: Bool) -> MenuRow {
    MenuRow(
      id: "systemDarkMenuBar", title: "System dark menu bar (test)", symbol: nil,
      kind: .toggle(.systemDarkMenuBar, isOn: clientAvailable && suspendsKey, enabled: clientAvailable && canToggle))
  }

  public mutating func start() -> [Effect] {
    phase == .needsRestore ? restore() : []
  }

  public mutating func toggle() -> [Effect] {
    guard canToggle else { return [] }
    guard phase == .off else { return restore() }
    phase = .enabling
    resumeKeyDuringRestore = false
    let request = makeRequest(enabled: true)
    enableRequest = request
    return [.send(request)]
  }

  public mutating func quit() -> [Effect] {
    guard !quitting else { return [] }
    quitting = true
    switch phase {
    case .off: return finishQuit(true)
    case .enableTimedOut: return finishQuit(false)
    case .enabling, .restoring: return []
    case .active, .needsRestore: return restore()
    }
  }

  public mutating func timeout(_ request: Request) -> [Effect] {
    if request == enableRequest && phase == .enabling {
      // The enable may still reach the server. The defensive false cannot clear its marker.
      phase = .enableTimedOut
      let defensive = sendRestore()
      return [defensive] + finishQuit(false)
    }
    if request == latestRestore && phase == .restoring {
      // A late reply can still prove restoration. Allow a new attempt if it never comes.
      phase = .needsRestore
      return finishQuit(false)
    }
    return []
  }

  public mutating func complete(_ request: Request, reply: Reply) -> [Effect] {
    if request.enabled {
      guard request == enableRequest else { return [] }
      enableRequest = nil
      return completeEnable(reply)
    }
    guard pendingRestores.remove(request) != nil, request == latestRestore else { return [] }
    latestRestore = nil
    guard phase == .restoring || phase == .needsRestore else { return [] }
    guard reply == .applied else {
      phase = .needsRestore
      return finishQuit(false)
    }
    phase = .off
    return [.clearMarker] + finishQuit(true)
  }

  private mutating func completeEnable(_ reply: Reply) -> [Effect] {
    switch reply {
    case .applied:
      let shouldRestore = phase == .enableTimedOut || quitting
      phase = .active
      return shouldRestore ? restore() : []
    case .uncertain:
      // An error can follow delivery. Bring back the key, but wait for an acknowledged false.
      resumeKeyDuringRestore = true
      return restore()
    case .notSent:
      phase = .off
      return [.clearMarker] + finishQuit(true)
    }
  }

  private mutating func restore() -> [Effect] {
    phase = .restoring
    return [sendRestore()]
  }

  private mutating func sendRestore() -> Effect {
    let request = makeRequest(enabled: false)
    latestRestore = request
    pendingRestores.insert(request)
    return .send(request)
  }

  private mutating func finishQuit(_ allowed: Bool) -> [Effect] {
    guard quitting else { return [] }
    quitting = false
    return [.finishQuit(allowed)]
  }

  private mutating func makeRequest(enabled: Bool) -> Request {
    sequence += 1
    return Request(id: sequence, enabled: enabled)
  }
}
