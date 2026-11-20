import XCTest
@testable import TopNVCore

final class BarTableTests: XCTestCase {
  private let kinds: [BarSceneKind] = [.desktop, .revealed, .overview, .fullScreen, .sliding, .unknown, .absent]

  private struct Inputs {
    let bits: Int
    var band: Bool { bits & 1 != 0 }
    var corners: Bool { bits & 2 != 0 }
    var failed: Bool { bits & 4 != 0 }
    var menu: Bool { bits & 8 != 0 }
    var entrance: Bool { bits & 16 != 0 }

    func cell(_ part: BarPart, kind: BarSceneKind) -> BarCell {
      BarTable.cell(part, kind: kind, bandEnabled: band, cornersWanted: corners,
                    keyFailed: failed, menuMeasured: menu, entrance: entrance, entrancePermitted: kind == .desktop)
    }

    func fixture(_ kind: BarSceneKind) -> BarPlanFixture {
      BarPlanFixture(kind: kind, band: band, corners: corners, failed: failed, measured: menu, active: [1])
    }
  }

  private struct Row {
    let part: BarPart
    let normal: [BarCell]
    let entering: BarCell

    func expected(at index: Int, inputs: Inputs) -> BarCell {
      switch part {
      case .corner: if !inputs.corners { return .closed }
      case .key, .plate, .lamp: if !inputs.band || inputs.failed { return .closed }
      case .edge:
        if !inputs.band { return .closed }
        if !inputs.menu { return .hidden }
      case .band: if !inputs.band { return .closed }
      }
      return index == 0 && inputs.band && inputs.entrance ? entering : normal[index]
    }
  }

  func testEveryCellMatchesTheConfirmedTable() {
    let visible: [BarCell] = [.visible, .hidden, .hidden, .visible, .visible, .visible, .hold]
    let gated: [BarCell] = [.gate, .gate, .gate, .gate, .gate, .gate, .hold]
    let measured: [BarCell] = [.visible, .hidden, .hidden, .hidden, .hidden, .hidden, .hidden]
    let rows = [Row(part: .lamp, normal: gated, entering: .path), Row(part: .band, normal: visible, entering: .path),
                Row(part: .key, normal: gated, entering: .path),
                Row(part: .plate, normal: gated, entering: .path), Row(part: .edge, normal: measured, entering: .path)]
      + ScreenCorner.allCases.map { Row(part: .corner($0), normal: visible, entering: .fade) }
    for row in rows {
      for (index, kind) in kinds.enumerated() {
        for bits in 0..<32 {
          let inputs = Inputs(bits: bits)
          XCTAssertEqual(inputs.cell(row.part, kind: kind), row.expected(at: index, inputs: inputs),
                         "\(row.part) \(kind) flags=\(bits)")
        }
      }
    }
  }

  func testAlphaIsZeroOrOneOutsideAnEntrance() {
    for kind in kinds {
      for bits in 0..<32 {
        let inputs = Inputs(bits: bits)
        if inputs.entrance && inputs.band && kind == .desktop { continue }
        guard let plan = inputs.fixture(kind).plan(elapsedMS: inputs.entrance ? 180 : nil) else {
          XCTAssertFalse(inputs.band || inputs.corners)
          continue
        }
        if inputs.band || inputs.corners { XCTAssertEqual(plan.kind, kind) }
        let alphas = [plan.band.alpha, plan.edge.alpha] + plan.corners.values.map(\.alpha)
          + Array(plan.key.gates.values)
        for alpha in alphas {
          switch alpha {
          case .value(let value): XCTAssertTrue(value == 0 || value == 1, "\(kind): \(value)")
          case .hold: XCTAssertEqual(kind, .absent)
          }
        }
      }
    }
  }

  func testFullScreenPermissionMasksOnlyThePartsOfAnActiveEntrance() {
    let parts: [BarPart] = [.band, .key, .plate, .lamp, .edge]
      + ScreenCorner.allCases.map { .corner($0) }
    for bits in 0..<32 {
      let inputs = Inputs(bits: bits)
      for permitted in [false, true] {
        for part in parts {
          let regular = inputs.cell(part, kind: .fullScreen)
          var expected = regular
          if permitted && inputs.band && inputs.entrance {
            switch part {
            case .band: expected = .path
            case .key, .plate, .lamp: expected = inputs.failed ? .closed : .path
            case .corner: expected = inputs.corners ? .fade : .closed
            case .edge: expected = .hidden
            }
          }
          let actual = BarTable.cell(
            part, kind: .fullScreen, bandEnabled: inputs.band, cornersWanted: inputs.corners,
            keyFailed: inputs.failed, menuMeasured: inputs.menu, entrance: inputs.entrance,
            entrancePermitted: permitted)
          XCTAssertEqual(actual, expected, "\(part) flags=\(bits) permitted=\(permitted)")
        }
      }
    }
  }

  func testNoPartExistsWhenItsCellIsClosed() {
    for kind in kinds {
      for bits in 0..<32 {
        let inputs = Inputs(bits: bits)
        let plan = inputs.fixture(kind).plan(elapsedMS: inputs.entrance ? 180 : nil)
        XCTAssertEqual(plan?.band.exists == true, inputs.cell(.band, kind: kind) != .closed)
        XCTAssertEqual(plan?.key.exists == true, inputs.cell(.key, kind: kind) != .closed)
        XCTAssertEqual(plan?.edge.exists == true, inputs.cell(.edge, kind: kind) != .closed)
        if inputs.cell(.plate, kind: kind) == .closed { XCTAssertNil(plan?.key.plate) }
        for corner in ScreenCorner.allCases {
          XCTAssertEqual(plan?.corners[corner]?.exists == true, inputs.cell(.corner(corner), kind: kind) != .closed)
        }
      }
    }
  }

  func testCornerAlphaNeverDecreasesDuringAnEntrance() {
    var previous = 0.0
    for time in -600...2000 {
      let alpha = BarEntranceMask.cornerAlpha(elapsedMS: Double(time))
      XCTAssertGreaterThanOrEqual(alpha, previous, "elapsedMS=\(time)")
      XCTAssertLessThanOrEqual(alpha, 1)
      if time <= 0 { XCTAssertEqual(alpha, 0) }
      previous = alpha
    }
    XCTAssertEqual(previous, 1)
  }
}
