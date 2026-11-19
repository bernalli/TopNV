import Foundation

public enum SpaceDirection { case left, right }

/// One snapshot of the main display. SkyLight's array order is the desktop order.
public struct ManagedDisplaySpaces {
  public enum InventoryError: Error { case missingDisplay, invalidSpaces, unsupportedType }

  private struct Space {
    let id: UInt64
    let type: Int

    init(_ entry: [String: Any]) throws {
      guard let id = Self.identifier(entry), let number = entry["type"] as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(), let type = Int(number.stringValue) else {
        throw InventoryError.invalidSpaces
      }
      self.id = id
      self.type = type
    }

    static func identifier(_ entry: [String: Any]) -> UInt64? {
      guard let number = (entry["ManagedSpaceID"] ?? entry["id64"]) as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(), let id = UInt64(number.stringValue), id > 0 else {
        return nil
      }
      return id
    }

    var supportsSwitch: Bool { type == 0 || type == 4 }
  }

  public let identifier: String
  public let mainUUID: String
  private let spaces: [Space]
  private let currentIndex: Int
  public var currentID: UInt64 { spaces[currentIndex].id }

  public init(_ displays: [[String: Any]], mainUUID: String) throws {
    let matches = displays.filter {
      guard let name = $0["Display Identifier"] as? String else { return false }
      return name == "Main" || name.caseInsensitiveCompare(mainUUID) == .orderedSame
    }
    guard matches.count == 1, let display = matches.first, let name = display["Display Identifier"] as? String else {
      throw InventoryError.missingDisplay
    }
    guard let entries = display["Spaces"] as? [[String: Any]], let active = display["Current Space"] as? [String: Any],
          let current = Space.identifier(active) else { throw InventoryError.invalidSpaces }
    let spaces = try entries.map(Space.init)
    guard Set(spaces.map(\.id)).count == spaces.count,
          let index = spaces.firstIndex(where: { $0.id == current }) else { throw InventoryError.invalidSpaces }
    self.spaces = spaces
    self.mainUUID = mainUUID
    identifier = name
    currentIndex = index
  }

  public func neighbor(_ direction: SpaceDirection) throws -> UInt64? {
    let index = currentIndex + (direction == .left ? -1 : 1)
    guard spaces.indices.contains(index) else { return nil }
    guard spaces[currentIndex].supportsSwitch, spaces[index].supportsSwitch else {
      throw InventoryError.unsupportedType
    }
    return spaces[index].id
  }
}
