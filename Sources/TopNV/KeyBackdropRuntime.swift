import BackdropRuntime
import Foundation
import QuartzCore
import TopNVCore

@MainActor
protocol KeyBackdropRuntime {
  func create(matrix: [Float], bounds: CGRect, scale: CGFloat, display: UInt32) throws -> CALayer
  func attach(root: CALayer, backdrop: CALayer, display: UInt32) throws
  func installPair(on glyph: CALayer) throws -> KeyBackdropPair
  func flush() throws
  func recommit(_ backdrop: CALayer) throws
  func detach(_ backdrop: CALayer) throws
}

@MainActor
protocol KeyBackdropPair {
  var pressed: CALayer { get }
  func verifyCommit() throws
  func remove()
}

extension KOTwoLayerBackdrop: KeyBackdropPair {
  func verifyCommit() throws {
    var reason: NSString?
    guard recommit(&reason) else { throw BackdropFailure(reason: reason as String? ?? "pair readback differs") }
  }
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
  }

  func installPair(on glyph: CALayer) throws -> KeyBackdropPair {
    var reason: NSString?
    let curve = ColorimeterKey.curve.values.map { NSNumber(value: $0) }
    guard let pair = KOInstallTwoLayer(glyph, ColorimeterKey.glyph.matrix, curve, ColorimeterKey.threshold.matrix,
                                       ColorimeterKey.pressedLevel, &reason) else {
      throw BackdropFailure(reason: reason as String? ?? "second layer unavailable")
    }
    return pair
  }

  func flush() throws { try checked { KOFlushBackdrop(&$0) } }

  func recommit(_ backdrop: CALayer) throws {
    try checked { KORecommitBackdrop(backdrop, LuminanceKey.normal.matrix, &$0) }
  }

  func detach(_ backdrop: CALayer) throws {
    try checked { KODetachBackdrop(backdrop, &$0) }
  }

  private func checked(_ operation: (inout NSString?) -> Bool) throws {
    var reason: NSString?
    guard operation(&reason) else { throw BackdropFailure(reason: reason as String? ?? "layer unavailable") }
  }
}
