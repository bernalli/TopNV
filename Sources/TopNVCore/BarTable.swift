public enum BarCell: Equatable, Sendable {
  case closed, hidden, visible, hold, gate, path, fade
}

/// Part    | desktop                   | revealed | overview  | fullScreen | sliding | unknown | absent
/// --------|---------------------------|----------|-----------|------------|---------|---------|-------
/// band    | visible (entrance: path)  | hidden   | hidden    | visible    | visible | visible | hold
/// key     | gate (entrance: path)     | gate (0) | gate (0)  | gate       | gate    | gate    | hold
/// lamp    | follows the active light-appearance key on the desktop, hidden in other scenes
/// plate   | follows its key in every scene
/// edge    | measured: visible or path | hidden   | hidden    | hidden     | hidden  | hidden  | hidden
/// corner  | visible (entrance: fade)  | hidden   | hidden    | visible    | visible | visible | hold
///
/// An unmeasured desktop edge is hidden. Overview retains the system window behavior.
/// A disabled band closes band, key, plate and edge. Unwanted corners close independently.
/// A failed key closes the key, lamp and plate. Key commands always come from the scene's
/// per-window decision, including during a masked entrance. Missing commands retain the gate.
public enum BarTable {
  // The public table takes one argument for each independent input.
  // swiftlint:disable:next function_parameter_count
  public static func cell(_ part: BarPart, kind: BarSceneKind, bandEnabled: Bool, cornersWanted: Bool,
                          keyFailed: Bool, menuMeasured: Bool, entrance: Bool) -> BarCell {
    let entering = entrance && bandEnabled && kind == .desktop
    switch part {
    case .lamp:
      guard bandEnabled, !keyFailed else { return .closed }
      guard kind == .desktop else { return .hidden }
      return entering ? .path : .gate
    case .key, .plate:
      guard bandEnabled, !keyFailed else { return .closed }
      if kind == .absent { return .hold }
      return entering ? .path : .gate
    case .edge:
      guard bandEnabled else { return .closed }
      guard kind == .desktop, menuMeasured else { return .hidden }
      return entering ? .path : .visible
    case .band:
      guard bandEnabled else { return .closed }
      return baseCell(kind: kind, entering: entering, effect: .path)
    case .corner:
      guard cornersWanted else { return .closed }
      return baseCell(kind: kind, entering: entering, effect: .fade)
    }
  }

  private static func baseCell(kind: BarSceneKind, entering: Bool, effect: BarCell) -> BarCell {
    if entering { return effect }
    switch kind {
    case .absent: return .hold
    case .revealed, .overview: return .hidden
    case .desktop, .fullScreen, .sliding, .unknown: return .visible
    }
  }
}
