import Foundation

public struct CornerRadiusOption: Identifiable, Equatable {
  public static let presets: [Double] = [5, 10, 15, 20, 25, 30]

  public let value: Double
  public let isCustom: Bool
  public var id: Double { value }

  public var title: String {
    let text = String(value)
    let points = text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    return isCustom ? "Custom (\(points) pt)" : "\(points) pt"
  }

  public static func options(for storedRadius: Double) -> [Self] {
    let presets = Self.presets.map { Self(value: $0, isCustom: false) }
    // Preserve the actual selection, including legacy values between presets.
    guard !Self.presets.contains(storedRadius) else { return presets }
    return presets + [Self(value: storedRadius, isCustom: true)]
  }
}
