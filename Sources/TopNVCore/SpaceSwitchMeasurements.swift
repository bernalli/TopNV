import Foundation

/// Correlates global workspace notifications with independently timed switch requests.
package struct SpaceSwitchMeasurements {
  package struct Sample: Sendable {
    package let received: DispatchTime
    package let current: UInt64?
  }

  package struct Request: Sendable {
    package let identifier = UUID()
    package let display: String
    package let origin: UInt64
    package let target: UInt64
    package let start: DispatchTime
    package var deadline: DispatchTime { start + .seconds(2) }
    package fileprivate(set) var lastUnmatched: Sample?

    package init(display: String, origin: UInt64, target: UInt64, start: DispatchTime) {
      self.display = display
      self.origin = origin
      self.target = target
      self.start = start
    }
  }

  private var pending: [Request] = []

  package init() {}

  package var isEmpty: Bool { pending.isEmpty }

  package mutating func record(_ request: Request) {
    pending.append(request)
  }

  package mutating func observe(display: String?, current: UInt64?, at received: DispatchTime) -> [Request] {
    var matched: [Request] = []
    pending = pending.compactMap { request in
      guard request.start <= received, received < request.deadline else { return request }
      let observed = display == request.display ? current : nil
      if observed == request.target {
        matched.append(request)
        return nil
      }
      guard observed != nil || request.lastUnmatched?.current == nil else { return request }
      var unresolved = request
      unresolved.lastUnmatched = Sample(received: received, current: observed)
      return unresolved
    }
    return matched
  }

  package mutating func expire(_ identifier: UUID) -> Request? {
    guard let index = pending.firstIndex(where: { $0.identifier == identifier }) else { return nil }
    return pending.remove(at: index)
  }

  package mutating func drain() -> [Request] {
    let requests = pending
    pending.removeAll()
    return requests
  }
}
