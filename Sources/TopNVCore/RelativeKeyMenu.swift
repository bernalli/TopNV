extension MenuRow {
  public static func lampUnderKey(enabled: Bool) -> Self {
    MenuRow(id: "lampUnderKey", title: "Lamp under key (test)", symbol: nil,
            kind: .toggle(.lampUnderKey, isOn: enabled, enabled: true))
  }

  public static func relativeKey(available: Bool, enabled: Bool) -> Self {
    MenuRow(id: "relativeKey", title: "Relative key (test)", symbol: nil,
            kind: .toggle(.relativeKey, isOn: available && enabled, enabled: available))
  }
}
