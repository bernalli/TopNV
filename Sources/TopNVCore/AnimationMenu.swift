extension BarAnimation {
  var name: String {
    switch self {
    case .curtain: "Sipario di velluto"
    case .ink: "Filo d’inchiostro"
    case .arrows: "Punte di freccia"
    case .breath: "Doppio respiro"
    case .calm: "Scorrimento calmo"
    case .stretch: "Notch che si allunga"
    case .blind: "Filo e tenda"
    case .wave: "Onda lenta"
    }
  }
}

extension MenuLayout {
  static func animationPreview(for state: MenuState) -> MenuRow {
    let calm = MenuRow(id: "previewCalm", title: "\(BarAnimation.calm.name) — fable", symbol: nil,
                       kind: .action(.previewCalm, enabled: true, key: ""))
    return MenuRow(id: "animationPreview", title: "Animation preview", symbol: nil,
                   kind: .submenu([calm], enabled: state.hideNotch && !state.menuBarBackground))
  }
}
