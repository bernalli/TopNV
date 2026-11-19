import CoreGraphics

public enum BarAlpha: Equatable, Sendable {
  case value(Double), hold
}

public struct BarPartPlan: Equatable, Sendable {
  public let exists: Bool
  public let frame: CGRect?
  public let pixels: PixelRect?
  public let alpha: BarAlpha
  public let mask: BarMask

  fileprivate var solidPixels: PixelRect? {
    alpha == .value(1) && mask == .none ? pixels : nil
  }
}

public struct BarKeyPlan: Equatable, Sendable {
  public let exists: Bool
  public let frame: CGRect?
  /// Geometry to install when creating a key. Existing plates keep their original geometry.
  public let plate: BarPlate?
  public let gates: [Int: BarAlpha]
  public let close: [Int]
  public let create: BarKeyCreation?
  public let mask: BarMask
  public let backdropExtent: CGRect?
}

public struct BarDisplayPlan: Equatable, Sendable {
  /// The sample used for pixel conversion and the backing scale of a newly created key.
  public let geometry: BarDisplay?
  public let kind: BarSceneKind
  public let bandEnabled: Bool
  public let band: BarPartPlan
  public let edge: BarPartPlan
  public let key: BarKeyPlan
  public let corners: [ScreenCorner: BarPartPlan]
  public let blackBottom: Int
}

public struct BarPlan: Equatable, Sendable {
  public let displays: [UInt32: BarDisplayPlan]
}

public enum BarSurface {
  /// The scene has already applied the settings at rebuild, including ownership across Space changes.
  public static func plan(geometry: [UInt32: BarDisplay], scene: BarScene, entrance: [UInt32: BarEntrance],
                          settings _: BarSettings) -> BarPlan {
    let ids = Set(geometry.keys).union(scene.bandFrames.keys).union(scene.cornerDisplays)
    var displays: [UInt32: BarDisplayPlan] = [:]
    for id in ids {
      displays[id] = displayPlan(id: id, display: geometry[id], scene: scene, entrance: entrance[id])
    }
    return BarPlan(displays: displays)
  }

  private static func displayPlan(id: UInt32, display: BarDisplay?, scene: BarScene,
                                  entrance: BarEntrance?) -> BarDisplayPlan {
    let kind = scene.kinds[id] ?? (display == nil ? .absent : .unknown)
    let bandFrame = scene.bandFrames[id]
    let bandEnabled = bandFrame != nil
    let cornersWanted = scene.cornerDisplays.contains(id)
    let menu = scene.evidence(display: id)?.menuBounds
    func cell(_ part: BarPart) -> BarCell {
      BarTable.cell(part, kind: kind, bandEnabled: bandEnabled, cornersWanted: cornersWanted,
                    keyFailed: scene.keyFailed || !scene.appliedHideNotch, menuMeasured: menu != nil,
                    entrance: entrance != nil)
    }

    let bandCell = cell(.band)
    var mask = BarMask.none
    if bandCell == .path, let entrance, let bandFrame, let display {
      mask = BarEntranceMask.band(elapsedMS: entrance.elapsedMS, bandSize: bandFrame.size,
                                  notchWidth: display.notchWidth)
    }
    func part(_ cell: BarCell, frame: CGRect?, mask: BarMask = .none, heldAlpha: BarAlpha = .hold) -> BarPartPlan {
      let alpha = cell.partAlpha(elapsedMS: entrance?.elapsedMS ?? 0, held: heldAlpha)
      let pixels = display.flatMap { BarGeometry.pixels(frame, on: $0) }
      return BarPartPlan(exists: cell != .closed, frame: frame, pixels: pixels, alpha: alpha, mask: mask)
    }
    let band = part(bandCell, frame: bandFrame, mask: mask)
    let edgeCell = cell(.edge)
    let edgeFrame = edgeCell == .visible || edgeCell == .path ? BarGeometry.edge(menuBounds: menu) : nil
    var edgeMask = BarMask.none
    if edgeCell == .path, let bandFrame, let edgeFrame {
      edgeMask = BarEntranceMask.edge(band: mask, bandFrame: bandFrame, edgeFrame: edgeFrame)
    }
    let edge = part(edgeCell, frame: edgeFrame, mask: edgeMask)
    let key = keyPlan(id: id, cell: cell(.key), band: band, display: display, scene: scene)

    var corners: [ScreenCorner: BarPartPlan] = [:]
    let frames = display.map { BarGeometry.corners(display: $0.frame, bandHeight: bandFrame?.height,
                                                   rounded: cornersWanted) } ?? [:]
    for corner in ScreenCorner.allCases {
      let cornerCell = cell(.corner(corner))
      if cornerCell == .hold {
        // Keep the window in place and restore its remembered base alpha after a partial fade.
        let base = (scene.visibility[id] ?? true) ? 1.0 : 0.0
        corners[corner] = part(.hold, frame: nil, heldAlpha: .value(base))
      } else if let frame = frames[corner] {
        corners[corner] = part(cornerCell, frame: frame)
      }
    }
    return BarDisplayPlan(geometry: display, kind: kind, bandEnabled: bandEnabled, band: band, edge: edge, key: key,
                          corners: corners, blackBottom: BarGeometry.blackBottom(band: band.solidPixels,
                                                                                edge: edge.solidPixels))
  }

  private static func keyPlan(id: UInt32, cell: BarCell, band: BarPartPlan,
                              display: BarDisplay?, scene: BarScene) -> BarKeyPlan {
    let exists = cell != .closed
    let keyFrame = exists ? band.frame : nil
    let plate = keyFrame.flatMap { frame in
      display.map { BarGeometry.plate(keySize: frame.size, menuHeight: $0.frame.maxY - $0.visibleFrame.maxY,
                                      scale: $0.scale) }
    }
    let decision = cell == .gate || cell == .path ? scene.keyDecisions[id] : nil
    let create = decision?.create.map { BarKeyCreation(instance: scene.keyInstances[id] ?? 0, reservation: $0) }
    let keyMask: BarMask = cell == .path ? band.mask : .none
    let extent = keyMask == .none ? nil : keyFrame.map {
      BarEntranceMask.keyBackdropExtent(band: keyMask, bandSize: $0.size)
    }
    return BarKeyPlan(exists: exists, frame: keyFrame, plate: plate,
                      gates: decision?.gates.mapValues { .value($0 ? 1 : 0) } ?? [:],
                      close: decision?.close ?? [], create: create, mask: keyMask, backdropExtent: extent)
  }
}

private extension BarCell {
  func partAlpha(elapsedMS: Double, held: BarAlpha) -> BarAlpha {
    switch self {
    case .closed, .hidden: return .value(0)
    case .visible, .path: return .value(1)
    case .hold: return held
    case .fade: return .value(BarEntranceMask.cornerAlpha(elapsedMS: elapsedMS))
    case .gate: preconditionFailure("Key gates require per-window commands")
    }
  }
}
