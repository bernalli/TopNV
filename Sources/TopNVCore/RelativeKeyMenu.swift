import Foundation

public struct LampKeyPreset: Sendable {
  public static let standard = Self(number: 2, command: .lampKey2, black: 0.94, white: 0.15)
  public static let choices = [
    Self(number: 1, command: .lampKey1, black: 0.97, white: 0.15), standard,
    Self(number: 3, command: .lampKey3, black: 0.90, white: 0.15),
    Self(number: 4, command: .lampKey4, black: 0.86, white: 0.15),
    Self(number: 5, command: .lampKey5, black: 0.94, white: 0.30)
  ]

  public let number: Int
  public let command: MenuCommand
  private let black: Float
  private let white: Float

  public var key: LuminanceKey { .from(black: black, white: white) }
  public var blackText: String { String(format: "%.2f", black) }
  public var whiteText: String { String(format: "%.2f", white) }
}

extension MenuRow {
  public static func lampKey(selected: LampKeyPreset) -> Self {
    let rows = LampKeyPreset.choices.map { preset in
      MenuRow(id: preset.command.rawValue,
              title: "\(preset.number)  black from \(preset.blackText), white to \(preset.whiteText)", symbol: nil,
              kind: .toggle(preset.command, isOn: preset.command == selected.command, enabled: true))
    }
    return MenuRow(id: "lampKey", title: "Lamp key (test)", symbol: nil, kind: .submenu(rows, enabled: true))
  }

  public static func lampOnly(enabled: Bool) -> Self {
    MenuRow(id: "lampOnly", title: "Lamp only (test)", symbol: nil,
            kind: .toggle(.lampOnly, isOn: enabled, enabled: true))
  }

  public static func lampUnderKey(enabled: Bool) -> Self {
    MenuRow(id: "lampUnderKey", title: "Lamp under key (test)", symbol: nil,
            kind: .toggle(.lampUnderKey, isOn: enabled, enabled: true))
  }

  public static func relativeKey(available: Bool, enabled: Bool) -> Self {
    MenuRow(id: "relativeKey", title: "Relative key (test)", symbol: nil,
            kind: .toggle(.relativeKey, isOn: available && enabled, enabled: available))
  }
}
