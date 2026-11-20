import Foundation

public enum BarPart: Hashable, Comparable, Sendable {
  case band, lamp, key, plate, edge, corner(ScreenCorner)

  public var token: String {
    switch self {
    case .lamp: return "lamp"
    case .band: return "band"
    case .key: return "key"
    case .plate: return "plate"
    case .edge: return "edge"
    case .corner(let corner): return "corner.\(corner.rawValue)"
    }
  }

  private var order: Int {
    switch self {
    case .band: return -1
    case .lamp: return 0
    case .key: return 1
    case .plate: return 2
    case .edge: return 3
    case .corner(.topLeft): return 4
    case .corner(.topRight): return 5
    case .corner(.bottomLeft): return 6
    case .corner(.bottomRight): return 7
    }
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
}

public struct BarRegistryID: Hashable, Comparable, Sendable {
  public let display: UInt32
  public let part: BarPart
  public let keyWindow: Int?

  public init(display: UInt32, part: BarPart, keyWindow: Int? = nil) {
    self.display = display
    self.part = part
    self.keyWindow = part == .key || part == .plate ? keyWindow : nil
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    if lhs.display != rhs.display { return lhs.display < rhs.display }
    if lhs.part != rhs.part { return lhs.part < rhs.part }
    guard let left = lhs.keyWindow else { return rhs.keyWindow != nil }
    guard let right = rhs.keyWindow else { return false }
    return left < right
  }
}

public enum BarMaskToken: Equatable, Sendable {
  case none, empty, bounds(PixelRect)

  fileprivate var token: String {
    switch self {
    case .none: return "none"
    case .empty: return "empty"
    case .bounds(let pixels): return pixels.description
    }
  }
}

public struct BarRegistryEntry: Equatable, Sendable {
  public let pixels: PixelRect?
  public let alpha: Double
  public let level: Int
  public let window: Int?
  public let mask: BarMaskToken
  public let onActiveSpace: Bool

  public init(pixels: PixelRect?, alpha: Double, level: Int, window: Int?, mask: BarMaskToken, onActiveSpace: Bool) {
    self.pixels = pixels
    self.alpha = alpha
    self.level = level
    self.window = window
    self.mask = mask
    self.onActiveSpace = onActiveSpace
  }

  fileprivate func hasSameFields(as other: Self?) -> Bool {
    guard let other else { return false }
    return pixels == other.pixels && (alpha == other.alpha || (alpha.isNaN && other.alpha.isNaN))
      && level == other.level && window == other.window && mask == other.mask
  }
}

public struct BarRegistryDisplay: Equatable, Sendable {
  public let frame: CGRect
  public let scale: CGFloat
  public let scene: BarSceneKind
  public let bandEnabled: Bool
  public let blackBottom: Int

  public init(frame: CGRect, scale: CGFloat, scene: BarSceneKind, bandEnabled: Bool, blackBottom: Int) {
    self.frame = frame
    self.scale = scale
    self.scene = scene
    self.bandEnabled = bandEnabled
    self.blackBottom = blackBottom
  }
}

public struct BarRegistrySnapshot: Sendable {
  public let entries: [BarRegistryID: BarRegistryEntry]
  public let displays: [UInt32: BarRegistryDisplay]

  public init(entries: [BarRegistryID: BarRegistryEntry], displays: [UInt32: BarRegistryDisplay]) {
    self.entries = entries
    self.displays = displays
  }
}

private func decimal(_ value: Double) -> String {
  guard value.isFinite else { return "0" }
  if let integer = Int(exactly: value) { return String(integer) }
  var text = String(format: "%.3f", value)
  while text.last == "0" { text.removeLast() }
  if text.last == "." { text.removeLast() }
  return text == "-0" ? "0" : text
}

private struct Summary: Equatable {
  let width, height: Int
  let scale: CGFloat
  let scene: BarSceneKind
  let bandEnabled: Bool
  let blackBottom: Int

  init(_ display: BarRegistryDisplay) {
    scale = display.scale.isFinite ? display.scale : 0
    width = max(0, Int(exactly: (display.frame.size.width * scale).rounded()) ?? 0)
    height = max(0, Int(exactly: (display.frame.size.height * scale).rounded()) ?? 0)
    scene = display.scene
    bandEnabled = display.bandEnabled
    blackBottom = display.blackBottom
  }

  func line(display: UInt32) -> String {
    "display=\(display) scene=\(scene.rawValue) part=summary band=\(bandEnabled ? "on" : "off")"
      + " screenPx=\(width)x\(height) scale=\(decimal(Double(scale))) blackBottom=\(blackBottom)"
  }
}

private enum Listed: Equatable {
  case window(PixelRect, Double), none, offspace, ambiguous, unavailable, plate

  var token: String {
    switch self {
    case let .window(pixels, alpha): return "\(pixels)/\(decimal(alpha))"
    case .none: return "none"
    case .offspace: return "offspace"
    case .ambiguous: return "ambiguous"
    case .unavailable: return "unavailable"
    case .plate: return "n/a"
    }
  }

  func disagrees(with previous: BarRegistryEntry?) -> Bool {
    guard let previous, previous.onActiveSpace, let applied = previous.pixels else { return false }
    switch self {
    case let .window(pixels, alpha): return pixels != applied || abs(alpha - previous.alpha) > 0.001
    case .none: return previous.alpha > 0.001
    default: return false
    }
  }
}

private struct Observation: Equatable {
  let listed: Listed
  let mismatch: Bool

  var suffix: String { " listed=\(listed.token)" + (mismatch ? " MISMATCH" : "") }
}

public struct BarRegistry {
  private typealias WindowIndex = [UInt32: [MenuBarEvidence.Window]]
  private let testCopy: Bool
  private var previous: [BarRegistryID: BarRegistryEntry] = [:]
  private var lastObservation: [BarRegistryID: Observation] = [:]
  private var summaries: [UInt32: Summary] = [:]

  public init(testCopy: Bool) { self.testCopy = testCopy }

  public static func blackBottom(band: BarRegistryEntry?, edge: BarRegistryEntry?) -> Int {
    [band, edge].compactMap { entry -> Int? in
      guard let entry, entry.alpha >= 0.999, entry.mask == .none else { return nil }
      return entry.pixels?.bottom
    }.max() ?? 0
  }

  public mutating func record(_ snapshot: BarRegistrySnapshot, ownWindows: [MenuBarEvidence.Window]?,
                              listedAgainst: BarRegistrySnapshot? = nil) -> [String] {
    let windows = testCopy ? ownWindows.map(Self.index) : nil
    let ids = Set(previous.keys).union(snapshot.entries.keys)
    let parts = Dictionary(grouping: ids.sorted(), by: \.display)
    let nextSummaries = snapshot.displays.mapValues(Summary.init)
    var lines: [String] = []
    for display in Set(parts.keys).union(nextSummaries.keys).sorted() {
      let info = snapshot.displays[display]
      if let summary = nextSummaries[display], summary != summaries[display] {
        lines.append(summary.line(display: display))
      }
      let scene = info?.scene ?? .absent
      for id in parts[display] ?? [] {
        if let entry = snapshot.entries[id] {
          let observation: Observation?
          if !testCopy {
            observation = nil
          } else if let collected = listedAgainst {
            if let atCollection = collected.entries[id], let number = atCollection.window, number == entry.window,
               let geometry = collected.displays[display],
               BarPixels.pixels(geometry.frame, display: geometry.frame, scale: geometry.scale) != nil {
              observation = Self.observe(id, atCollection, geometry, windows, atCollection)
            } else {
              observation = Observation(listed: .unavailable, mismatch: false)
            }
          } else {
            observation = Self.observe(id, entry, info, windows, previous[id])
          }
          let listingChanged = observation.map { $0.listed != .unavailable && $0 != lastObservation[id] } ?? false
          guard listingChanged || !entry.hasSameFields(as: previous[id]) else { continue }
          let prefix = "display=\(display) scene=\(scene.rawValue) part=\(id.part.token)"
          let pixels = entry.pixels?.description ?? "none"
          let number = entry.window.map { String($0) } ?? "none"
          lines.append(prefix + " px=\(pixels) alpha=\(decimal(entry.alpha)) level=\(entry.level)"
            + " window=\(number) mask=\(entry.mask.token)" + (observation?.suffix ?? ""))
          lastObservation[id] = observation
        } else if let closed = previous[id] {
          let prefix = "display=\(display) scene=\(scene.rawValue) part=\(id.part.token)"
          lines.append(prefix + " px=none alpha=0 level=\(closed.level) window=none mask=none"
            + (testCopy ? " listed=unavailable" : ""))
          lastObservation.removeValue(forKey: id)
        }
      }
    }
    previous = snapshot.entries
    summaries = nextSummaries
    return lines
  }

  private static func index(_ windows: [MenuBarEvidence.Window]) -> WindowIndex {
    var result: WindowIndex = [:]
    for window in windows where window.owner == .ownApp {
      if let number = window.number { result[number, default: []].append(window) }
    }
    return result
  }

  private static func observe(_ id: BarRegistryID, _ entry: BarRegistryEntry, _ display: BarRegistryDisplay?,
                              _ windows: WindowIndex?, _ previous: BarRegistryEntry?) -> Observation {
    let listed: Listed
    if let windows {
      let matches = entry.window.flatMap { UInt32(exactly: $0) }.flatMap { windows[$0] } ?? []
      if id.part == .plate {
        listed = .plate
      } else if matches.isEmpty {
        listed = entry.onActiveSpace ? .none : .offspace
      } else if matches.count > 1 {
        listed = .ambiguous
      } else if let window = matches.first, window.alpha.isFinite, let display,
                let pixels = BarPixels.pixels(window.bounds, display: display.frame, scale: display.scale) {
        listed = .window(pixels, window.alpha)
      } else {
        listed = .unavailable
      }
    } else {
      listed = .unavailable
    }
    return Observation(listed: listed, mismatch: listed.disagrees(with: previous))
  }
}
