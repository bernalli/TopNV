import BackdropRuntime
import Foundation
import QuartzCore
import TopNVCore

@MainActor
protocol KeyBackdropRuntime {
  func create(matrix: [Float], bounds: CGRect, scale: CGFloat, display: UInt32) throws -> CALayer
  func attach(root: CALayer, backdrop: CALayer, display: UInt32) throws
  func resize(_ backdrop: CALayer, to frame: CGRect)
  func flush() throws
  func recommit(_ backdrop: CALayer) throws
  func detach(_ backdrop: CALayer) throws
}

extension KeyBackdropRuntime {
  func resize(_ backdrop: CALayer, to frame: CGRect) { backdrop.frame = frame }
}

struct BackdropFailure: LocalizedError {
  let reason: String
  var errorDescription: String? { reason }
}

struct PrivateBackdropRuntime {}

extension PrivateBackdropRuntime: KeyBackdropRuntime {
  func create(matrix: [Float], bounds: CGRect, scale: CGFloat, display: UInt32) throws -> CALayer {
    var reason: NSString?
    let layer = matrix.withUnsafeBufferPointer { values -> CALayer? in
      guard let base = values.baseAddress else { return nil }
      return KOCreateBackdrop(base, values.count, bounds, scale, &reason)
    }
    guard let layer else { throw BackdropFailure(reason: reason as String? ?? "layer unavailable") }
    return layer
  }

  func attach(root: CALayer, backdrop: CALayer, display: UInt32) throws {
    try checked { KOAttachBackdrop(root, backdrop, &$0) }
    RelativeMenuBarKey.shared.observe(backdrop, display: display)
  }

  func resize(_ backdrop: CALayer, to frame: CGRect) {
    backdrop.frame = frame
    RelativeMenuBarKey.shared.resizePressed(on: backdrop)
  }

  func flush() throws { try checked { KOFlushBackdrop(&$0) } }

  func recommit(_ backdrop: CALayer) throws {
    guard !RelativeMenuBarKey.shared.recommitPair(on: backdrop) else { return }
    try checked { KORecommitBackdrop(backdrop, &$0) }
  }

  func detach(_ backdrop: CALayer) throws {
    RelativeMenuBarKey.shared.forget(backdrop)
    try checked { KODetachBackdrop(backdrop, &$0) }
  }

  private func checked(_ operation: (inout NSString?) -> Bool) throws {
    var reason: NSString?
    guard operation(&reason) else { throw BackdropFailure(reason: reason as String? ?? "layer unavailable") }
  }
}
