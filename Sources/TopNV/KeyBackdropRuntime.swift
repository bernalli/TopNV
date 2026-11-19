import BackdropRuntime
import Foundation
import QuartzCore
import TopNVCore

@MainActor
protocol KeyBackdropRuntime {
  func create(matrix: [Float], bounds: CGRect, scale: CGFloat) throws -> CALayer
  func attach(root: CALayer, backdrop: CALayer) throws
  func flush() throws
  func recommit(_ backdrop: CALayer) throws
  func detach(_ backdrop: CALayer) throws
}

struct BackdropFailure: LocalizedError {
  let reason: String
  var errorDescription: String? { reason }
}

struct PrivateBackdropRuntime {}

extension PrivateBackdropRuntime: KeyBackdropRuntime {
  func create(matrix: [Float], bounds: CGRect, scale: CGFloat) throws -> CALayer {
    var reason: NSString?
    let layer = matrix.withUnsafeBufferPointer { values -> CALayer? in
      guard let base = values.baseAddress else { return nil }
      return KOCreateBackdrop(base, values.count, bounds, scale, &reason)
    }
    guard let layer else { throw BackdropFailure(reason: reason as String? ?? "layer unavailable") }
    RelativeMenuBarKey.shared.observe(layer)
    return layer
  }

  func attach(root: CALayer, backdrop: CALayer) throws {
    try checked { KOAttachBackdrop(root, backdrop, &$0) }
  }

  func flush() throws { try checked { KOFlushBackdrop(&$0) } }

  func recommit(_ backdrop: CALayer) throws { try checked { KORecommitBackdrop(backdrop, &$0) } }

  func detach(_ backdrop: CALayer) throws { try checked { KODetachBackdrop(backdrop, &$0) } }

  private func checked(_ operation: (inout NSString?) -> Bool) throws {
    var reason: NSString?
    guard operation(&reason) else { throw BackdropFailure(reason: reason as String? ?? "layer unavailable") }
  }
}
