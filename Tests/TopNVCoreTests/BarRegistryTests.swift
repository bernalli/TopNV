import Foundation
import XCTest
import TopNVCore

final class BarRegistryTests: XCTestCase {
  private typealias Entry = BarRegistryEntry
  private typealias Window = MenuBarEvidence.Window
  private let frame = CGRect(x: -100, y: 20, width: 100, height: 80)
  private let pixels = PixelRect(x: 0, y: 0, width: 200, height: 4)
  private let band = BarRegistryID(display: 2, part: .band, keyWindow: nil)
  private let edge = BarRegistryID(display: 2, part: .edge, keyWindow: nil)

  private func entry(_ alpha: Double = 1, number: Int = 7, mask: BarMaskToken = .none,
                     active: Bool = true) -> Entry {
    Entry(pixels: pixels, alpha: alpha, level: 26, window: number, mask: mask, onActiveSpace: active)
  }

  private func window(_ alpha: Double = 1, offset: CGFloat = 0, owner: MenuBarEvidence.Owner = .ownApp) -> Window {
    Window(owner: owner, layer: 26, bounds: CGRect(x: -100 + offset, y: 98, width: 100, height: 2),
           alpha: alpha, number: 7)
  }

  private func display(_ scene: BarSceneKind = .desktop, scale: CGFloat = 2, bottom: Int = 4) -> BarRegistryDisplay {
    BarRegistryDisplay(frame: frame, scale: scale, scene: scene, bandEnabled: true, blackBottom: bottom)
  }

  private func snapshot(_ entries: [BarRegistryID: Entry]) -> BarRegistrySnapshot {
    BarRegistrySnapshot(entries: entries, displays: [2: display()])
  }

  func testLineFormatMatchesTheGrammar() {
    let parts: [(BarPart, String)] = [
      (.band, "band"), (.key, "key"), (.plate, "plate"), (.edge, "edge"),
      (.corner(.topLeft), "corner.topLeft"), (.corner(.topRight), "corner.topRight"),
      (.corner(.bottomLeft), "corner.bottomLeft"), (.corner(.bottomRight), "corner.bottomRight")
    ]
    var entries: [BarRegistryID: Entry] = [:]
    for (part, _) in parts.reversed() {
      let id = BarRegistryID(display: 2, part: part, keyWindow: part == .key || part == .plate ? 7 : nil)
      let mask: BarMaskToken = part == .key ? .empty : (part == .plate ? .bounds(pixels) : .none)
      entries[id] = entry(1.0 / 3, mask: mask)
    }
    let other = BarRegistryDisplay(frame: frame, scale: 1.25, scene: .revealed, bandEnabled: false, blackBottom: 0)
    let state = BarRegistrySnapshot(entries: entries, displays: [2: display(), 1: other])
    for copy in [false, true] {
      var registry = BarRegistry(testCopy: copy)
      var expected = ["display=1 scene=revealed part=summary band=off screenPx=125x100 scale=1.25 blackBottom=0",
                      "display=2 scene=desktop part=summary band=on screenPx=200x160 scale=2 blackBottom=4"]
      for (part, token) in parts {
        let mask = part == .key ? "empty" : (part == .plate ? "0,0,200,4" : "none")
        let listed = part == .plate ? "n/a" : "0,0,200,4/0.5"
        let line = "display=2 scene=desktop part=\(token) px=0,0,200,4 alpha=0.333 level=26 window=7 mask=\(mask)"
        expected.append(line + (copy ? " listed=\(listed)" : ""))
      }
      XCTAssertEqual(registry.record(state, ownWindows: [window(0.5)]), expected)
    }
  }

  func testOnlyChangedPartsProduceLines() {
    var registry = BarRegistry(testCopy: false)
    let key = BarRegistryID(display: 2, part: .key, keyWindow: 7)
    let other = BarRegistryID(display: 2, part: .key, keyWindow: 12)
    let state = snapshot([other: entry(number: 12), key: entry(), band: entry()])
    let lines = registry.record(state, ownWindows: [])
    XCTAssertEqual(lines.count, 4)
    XCTAssertTrue(lines.suffix(2).first?.contains("window=7 ") == true)
    XCTAssertTrue(lines.last?.contains("window=12 ") == true)
    XCTAssertEqual(registry.record(state, ownWindows: []), [])
    var entries = state.entries
    entries[band] = entry(active: false)
    entries[key] = entry(0.75)
    let changed = registry.record(snapshot(entries), ownWindows: [])
    XCTAssertEqual(changed, ["display=2 scene=desktop part=key px=0,0,200,4 alpha=0.75 level=26 window=7 mask=none"])
    let moved = BarRegistrySnapshot(entries: entries, displays: [2: display(.sliding)])
    XCTAssertEqual(registry.record(moved, ownWindows: []),
                   ["display=2 scene=sliding part=summary band=on screenPx=200x160 scale=2 blackBottom=4"])
  }

  func testAClosedPartProducesOneNoneLine() {
    let empty = BarRegistrySnapshot(entries: [:], displays: [:])
    for copy in [false, true] {
      var registry = BarRegistry(testCopy: copy)
      _ = registry.record(snapshot([edge: entry()]), ownWindows: [])
      let closed = "display=2 scene=absent part=edge px=none alpha=0 level=26 window=none mask=none"
      XCTAssertEqual(registry.record(empty, ownWindows: []), [closed + (copy ? " listed=unavailable" : "")])
      XCTAssertEqual(registry.record(empty, ownWindows: []), [])
      XCTAssertEqual(registry.record(snapshot([edge: entry()]), ownWindows: []).count, 2)
    }
  }

  func testListedAndMismatchAppearOnlyInTestCopies() {
    let state = snapshot([band: entry()])
    for copy in [false, true] {
      var registry = BarRegistry(testCopy: copy)
      let first = registry.record(state, ownWindows: nil)
      XCTAssertEqual(first.last?.contains(" listed=unavailable"), copy)
      let absent = registry.record(state, ownWindows: [window(owner: .application)])
      XCTAssertEqual(absent.count, copy ? 1 : 0)
      if copy { XCTAssertTrue(absent.first?.hasSuffix(" listed=none MISMATCH") == true) }
      XCTAssertEqual(registry.record(state, ownWindows: nil), [])
      XCTAssertEqual(registry.record(state, ownWindows: []), [])
      let present = registry.record(state, ownWindows: [window()])
      XCTAssertEqual(present.count, copy ? 1 : 0)
      if copy { XCTAssertTrue(present.first?.hasSuffix(" listed=0,0,200,4/1") == true) }
    }
  }

  func testMismatchComparesTheListWithThePreviousApplication() {
    var registry = BarRegistry(testCopy: true)
    let initial = snapshot([band: entry()])
    XCTAssertTrue(registry.record(initial, ownWindows: []).last?.hasSuffix(" listed=none") == true)
    let faded = snapshot([band: entry(0.5)])
    XCTAssertTrue(registry.record(faded, ownWindows: [window()]).last?.hasSuffix(" listed=0,0,200,4/1") == true)
    let staleAlpha = registry.record(faded, ownWindows: [window()])
    XCTAssertTrue(staleAlpha.last?.hasSuffix(" listed=0,0,200,4/1 MISMATCH") == true)
    XCTAssertEqual(registry.record(faded, ownWindows: [window()]), [])
    let staleBounds = registry.record(faded, ownWindows: [window(0.5, offset: 1)])
    XCTAssertTrue(staleBounds.last?.hasSuffix(" listed=2,0,200,4/0.5 MISMATCH") == true)
    XCTAssertTrue(registry.record(faded, ownWindows: [window(0.5005)]).last?.hasSuffix(" MISMATCH") == false)
  }

  func testOffSpaceAmbiguousAndHiddenWindowsAreNeverMismatches() {
    var registry = BarRegistry(testCopy: true)
    let visible = snapshot([edge: entry()])
    _ = registry.record(visible, ownWindows: [])
    let duplicates = registry.record(visible, ownWindows: [window(), window()])
    XCTAssertTrue(duplicates.first?.hasSuffix(" listed=ambiguous") == true)
    let inactive = snapshot([edge: entry(active: false)])
    XCTAssertTrue(registry.record(inactive, ownWindows: []).first?.hasSuffix(" listed=offspace") == true)
    XCTAssertTrue(registry.record(visible, ownWindows: []).first?.hasSuffix(" listed=none") == true)
    let hidden = snapshot([edge: entry(0)])
    _ = registry.record(hidden, ownWindows: [window()])
    XCTAssertTrue(registry.record(hidden, ownWindows: []).first?.hasSuffix(" listed=none") == true)
  }

  func testSummaryCarriesTheBlackBottomOfOpaqueBandAndEdge() {
    let lower = Entry(pixels: PixelRect(x: 0, y: 4, width: 200, height: 2), alpha: 0.999,
                      level: 27, window: 8, mask: .none, onActiveSpace: true)
    func check(_ band: Entry?, _ edge: Entry?, expected: Int) {
      let bottom = BarRegistry.blackBottom(band: band, edge: edge)
      XCTAssertEqual(bottom, expected)
      var registry = BarRegistry(testCopy: false)
      let state = BarRegistrySnapshot(entries: [:], displays: [2: display(bottom: bottom)])
      let lines = registry.record(state, ownWindows: nil)
      let summary = "display=2 scene=desktop part=summary band=on screenPx=200x160 scale=2 blackBottom=\(expected)"
      XCTAssertEqual(lines, [summary])
    }
    check(entry(), lower, expected: 6)
    check(entry(), entry(0), expected: 4)
    check(entry(mask: .empty), lower, expected: 6)
    check(entry(mask: .bounds(pixels)), entry(0), expected: 0)
    check(entry(0.9989), nil, expected: 0)
    check(nil, nil, expected: 0)
  }

  func testHostileSnapshotSequencesAreDeterministic() throws {
    let integer = #"-?(?:0|[1-9][0-9]*)"#
    let decimal = integer + #"(?:\.[0-9]{0,2}[1-9])?"#
    let rect = Array(repeating: integer, count: 4).joined(separator: ",")
    let prefix = #"^display=[0-9]+ scene=(?:desktop|revealed|overview|fullScreen|sliding|unknown|absent) part="#
    let part = #"(?:band|key|plate|edge|corner\.(?:topLeft|topRight|bottomLeft|bottomRight))"#
    let summary = #"summary band=(?:on|off) screenPx=[0-9]+x[0-9]+"# + " scale=\(decimal) blackBottom=\(integer)"
    let listed = "(?:\(rect)/\(decimal)|none|offspace|ambiguous|unavailable|n/a)"
    let fields = "\(part) px=(?:\(rect)|none) alpha=\(decimal) level=\(integer) window=(?:\(integer)|none)"
    let pattern = prefix + "(?:\(summary)|\(fields) mask=(?:none|empty|\(rect))(?: listed=\(listed)(?: MISMATCH)?)?)$"
    let grammar = try NSRegularExpression(pattern: pattern)
    var random = BarTestGenerator()
    for sequence in 0..<200 {
      var first = BarRegistry(testCopy: sequence.isMultiple(of: 2))
      var second = first
      var entries: [BarRegistryID: Entry] = [:]
      var listing: [Window]?
      var state = snapshot(entries)
      for step in 0..<30 {
        if step % 3 == 0 {
          let id = random.next(2) == 0 ? band : edge
          let alpha = [Double.nan, 0, 0.3333, 1][random.next(4)]
          entries[id] = random.next(4) == 0 ? nil : entry(alpha, active: random.next(2) == 0)
          let samples: [[Window]?] = [nil, [], [window()], [window(), window()], [window(.nan)], [window(offset: .nan)]]
          listing = samples[random.next(samples.count)]
          let scale: CGFloat = random.next(8) == 0 ? .nan : 2
          state = BarRegistrySnapshot(entries: entries, displays: [2: display(scale: scale)])
        }
        let lines = first.record(state, ownWindows: listing)
        XCTAssertEqual(lines, second.record(state, ownWindows: listing))
        // The second sample can change MISMATCH. The third has the same previous application too.
        if step % 3 == 2 { XCTAssertEqual(lines, []) }
        for line in lines {
          let range = NSRange(line.startIndex..., in: line)
          XCTAssertEqual(grammar.firstMatch(in: line, range: range)?.range, range, line)
        }
      }
    }
  }
}

extension BarRegistryTests {
  func testListingUsesTheWindowAndGeometryAtCollection() {
    let collected = snapshot([band: entry()])
    var registry = BarRegistry(testCopy: true)
    _ = registry.record(collected, ownWindows: [])
    let frame = snapshot([band: entry(0.25)])
    _ = registry.record(frame, ownWindows: nil, listedAgainst: collected)
    let resized = BarRegistrySnapshot(entries: [band: entry(0.5)], displays: [2: display(scale: 1)])
    let lines = registry.record(resized, ownWindows: [window()], listedAgainst: collected)
    XCTAssertTrue(lines.contains { $0.hasSuffix("listed=0,0,200,4/1") })

    let replacement = snapshot([band: entry(number: 9)])
    let replaced = registry.record(replacement, ownWindows: [window()], listedAgainst: collected)
    XCTAssertTrue(replaced.contains { $0.contains("window=9 ") && $0.hasSuffix("listed=unavailable") })
    let absent = BarRegistrySnapshot(entries: collected.entries, displays: [:])
    let missing = registry.record(collected, ownWindows: [window()], listedAgainst: absent)
    XCTAssertTrue(missing.contains { $0.hasSuffix("listed=unavailable") })
    let duplicate = registry.record(collected, ownWindows: [window(), window(offset: 3)], listedAgainst: collected)
    XCTAssertTrue(duplicate.contains { $0.hasSuffix("listed=ambiguous") })
  }
}
