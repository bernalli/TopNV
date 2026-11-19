extension MenuRow {
  public static func relativeKey(available: Bool, enabled: Bool) -> Self {
    MenuRow(id: "relativeKey", title: "Relative key (test)", symbol: nil,
            kind: .toggle(.relativeKey, isOn: available && enabled, enabled: available))
  }
}
