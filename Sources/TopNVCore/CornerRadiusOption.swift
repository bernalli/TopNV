import Foundation

public struct CornerRadiusOption: Identifiable, Equatable {
  public static let presets: [Double] = [5, 10, 15, 20, 25, 30]

  public let value: Double
  public let isCustom: Bool
  public var id: Double { value }

  private let localizer: Localizer

  public init(value: Double, isCustom: Bool, localizer: Localizer = .main) {
    self.value = value
    self.isCustom = isCustom
    self.localizer = localizer
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.value == rhs.value && lhs.isCustom == rhs.isCustom
  }

  public var title: String {
    let text = String(value)
    let points = text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    return localizer(isCustom ? .customRadius : .radius, points)
  }

  public static func options(for storedRadius: Double, localizer: Localizer = .main) -> [Self] {
    let presets = Self.presets.map { Self(value: $0, isCustom: false, localizer: localizer) }
    // Preserve the actual selection, including legacy values between presets.
    guard !Self.presets.contains(storedRadius) else { return presets }
    return presets + [Self(value: storedRadius, isCustom: true, localizer: localizer)]
  }
}
