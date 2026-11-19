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
    var rows = BarAnimation.allCases.compactMap { animation -> MenuRow? in
      guard let command = MenuCommand(rawValue: animation.rawValue),
            let author = animation.rawValue.split(separator: "-").first else { return nil }
      return MenuRow(id: command.rawValue, title: "\(animation.name) — \(author)", symbol: nil,
                     kind: .toggle(command, isOn: state.lastAnimation == animation, enabled: true))
    }
    rows.append(MenuRow(id: "replayAnimation", title: "Replay", symbol: nil,
                        kind: .action(.replayAnimation, enabled: state.lastAnimation != nil, key: "")))
    return MenuRow(id: "animationPreview", title: "Animation preview", symbol: nil,
                   kind: .submenu(rows, enabled: state.hideNotch))
  }
}
