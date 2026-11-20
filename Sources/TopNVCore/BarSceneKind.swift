public enum BarSceneKind: String, CaseIterable, Sendable {
  case desktop, revealed, overview, fullScreen, sliding, unknown, absent

  public static let overviewLayer = 19

  public static func classify(_ evidence: MenuBarEvidence.Result?, screenPresent: Bool) -> BarSceneKind {
    guard screenPresent else { return .absent }
    guard let evidence, evidence.context != .unknown else { return .unknown }
    if evidence.desktopRevealed {
      return evidence.revealLayer == overviewLayer ? .overview : .revealed
    }
    if evidence.spaceSliding { return .sliding }
    return evidence.desktopScene ? .desktop : .fullScreen
  }
}
