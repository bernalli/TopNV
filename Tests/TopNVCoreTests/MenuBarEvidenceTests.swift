import XCTest
@testable import TopNVCore

final class MenuBarEvidenceTests: XCTestCase {
  private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
  private let visible = CGRect(x: 0, y: 60, width: 1512, height: 888)
  private let strip = CGRect(x: 0, y: 948, width: 1512, height: 34)

  private var menu: MenuBarEvidence.Window {
    .init(owner: .windowServer, layer: 24, bounds: strip)
  }

  private func classify(_ windows: [MenuBarEvidence.Window]?,
                        visible: CGRect? = nil) -> MenuBarEvidence.Result {
    MenuBarEvidence.evaluate(frame: frame, visibleFrame: visible ?? self.visible,
                             bandFrame: strip, windows: windows)
  }

  private func app(_ bounds: CGRect, layer: Int = 0) -> MenuBarEvidence.Window {
    .init(owner: .application, layer: layer, bounds: bounds)
  }

  func testNoNamesOrWindowTitlesAreNeededForDesktopEvidence() {
    let result = classify([menu])
    XCTAssertEqual(result.context, .desktop)
    XCTAssertTrue(result.menuVisible)
  }

  func testTheMenuBarSurfaceNeedsNoExactLayerOrHeight() {
    for layer in [0, 24, 25] {
      for height in [CGFloat(24), 33, 34, 37, 68] {
        let bar = MenuBarEvidence.Window(
          owner: .windowServer, layer: layer,
          bounds: CGRect(x: 0, y: 982 - height, width: 1512, height: height))
        XCTAssertTrue(classify([bar]).menuVisible, "layer \(layer) height \(height)")
      }
    }
    let rejected: [MenuBarEvidence.Window] = [
      .init(owner: .windowServer, layer: -1, bounds: strip),
      .init(owner: .windowServer, layer: 24, bounds: frame),
      .init(owner: .windowServer, layer: 24, bounds: strip.offsetBy(dx: 0, dy: -3)),
      .init(owner: .windowServer, layer: 24, bounds: strip.offsetBy(dx: 0, dy: 3)),
      .init(owner: .windowServer, layer: 24, bounds: CGRect(x: 3, y: 948, width: 1509, height: 34)),
      .init(owner: .windowServer, layer: 24, bounds: CGRect(x: 0, y: 948, width: 1509, height: 34)),
      .init(owner: .windowServer, layer: 24, bounds: CGRect(x: 1400, y: 950, width: 30, height: 30)),
      .init(owner: .application, layer: 24, bounds: strip),
      .init(owner: .desktop, layer: 24, bounds: strip),
      .init(owner: .ownApp, layer: 24, bounds: strip),
    ]
    for window in rejected {
      XCTAssertFalse(classify([window]).menuVisible, "\(window.owner) \(window.layer) \(window.bounds)")
    }
  }

  /// With the Dock hidden or at a side a zoomed or tiled window reaches the bottom edge.
  func testZoomedAndTiledDesktopWindowsAreNotFullScreen() {
    let sideDock = CGRect(x: 60, y: 0, width: 1452, height: 949)
    let hiddenDock = CGRect(x: 0, y: 0, width: 1512, height: 949)
    for visible in [sideDock, hiddenDock] {
      let halves = [
        CGRect(x: visible.minX, y: 0, width: visible.width / 2, height: visible.height),
        CGRect(x: visible.midX, y: 0, width: visible.width / 2, height: visible.height),
      ]
      for bounds in [visible] + halves {
        for top in [CGFloat(946), 948, 949, 950] {
          var window = bounds
          window.size.height = top
          XCTAssertEqual(classify([menu, app(window)], visible: visible).context, .desktop,
                         "\(window)")
        }
      }
      XCTAssertEqual(classify([menu, app(halves[0]), app(halves[1])], visible: visible).context,
                     .desktop)
    }
  }

  func testAWindowFromTheBottomEdgeToTheTopEdgeBlocksAlsoWithTheMenuRevealed() {
    for width in [CGFloat(1512), 750, 605] {
      for x in [CGFloat(0), 1512 - width] {
        for top in [CGFloat(980), 982, 1000] {
          for layer in [0, 3, 24, 25, 26] {
            let window = app(CGRect(x: x, y: 0, width: width, height: top), layer: layer)
            XCTAssertEqual(classify([menu, window]).context, .fullScreen,
                           "x \(x) width \(width) top \(top) layer \(layer)")
          }
        }
      }
    }
    XCTAssertEqual(classify([menu], visible: frame).context, .fullScreen)
    XCTAssertEqual(
      classify([menu], visible: CGRect(x: 0, y: 0, width: 1512, height: 980)).context, .fullScreen)
  }

  func testWindowsThatCannotLieUnderTheEffectAreNotEvidence() {
    let full = frame
    for layer in [-2_147_483_622, -1, 27, 101, 1000, 2_147_483_630] {
      XCTAssertEqual(classify([menu, app(full, layer: layer)]).context, .desktop, "layer \(layer)")
    }
    for owner in [MenuBarEvidence.Owner.ownApp, .desktop, .windowServer] {
      XCTAssertEqual(classify([menu, .init(owner: owner, layer: 0, bounds: full)]).context,
                     .desktop)
    }
    // Narrow, not down to the bottom edge, or on another display.
    for bounds in [
      CGRect(x: 0, y: 0, width: 600, height: 982), CGRect(x: 0, y: 3, width: 1512, height: 979),
      CGRect(x: 1512, y: 0, width: 1920, height: 1080), CGRect(x: -1920, y: 0, width: 1920, height: 982),
    ] {
      XCTAssertEqual(classify([menu, app(bounds)]).context, .desktop, "\(bounds)")
    }
  }

  func testUnavailableOrMalformedEvidenceFailsClosed() {
    XCTAssertEqual(classify(nil).context, .unknown)
    XCTAssertFalse(classify(nil).menuVisible)
    XCTAssertFalse(classify([]).menuVisible)
    let malformed: [CGRect] = [
      .zero, .null, .infinite, CGRect(x: 0, y: 0, width: -1512, height: 982),
      CGRect(x: CGFloat.nan, y: 0, width: 1512, height: 982),
      CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 982),
      CGRect(x: 0, y: 0, width: 1512, height: CGFloat.nan),
    ]
    for rect in malformed {
      for result in [
        MenuBarEvidence.evaluate(frame: rect, visibleFrame: visible, bandFrame: strip, windows: [menu]),
        MenuBarEvidence.evaluate(frame: frame, visibleFrame: rect, bandFrame: strip, windows: [menu]),
        MenuBarEvidence.evaluate(frame: frame, visibleFrame: visible, bandFrame: rect, windows: [menu]),
      ] {
        XCTAssertEqual(result.context, .unknown, "\(rect)")
        XCTAssertFalse(result.menuVisible, "\(rect)")
      }
      // A malformed window is neither a menu bar nor a covering window.
      let result = classify([.init(owner: .windowServer, layer: 24, bounds: rect), app(rect)])
      XCTAssertFalse(result.menuVisible, "\(rect)")
      XCTAssertEqual(result.context, .desktop, "\(rect)")
    }
    // A visible frame or a band outside the screen.
    XCTAssertEqual(classify([menu], visible: frame.offsetBy(dx: 10, dy: 0)).context, .unknown)
    XCTAssertEqual(
      MenuBarEvidence.evaluate(frame: frame, visibleFrame: visible,
                               bandFrame: strip.offsetBy(dx: 0, dy: 40), windows: [menu]).context,
      .unknown)
  }

  func testNormalWindowBelowMenuAndAboveDockIsNotFullScreen() {
    XCTAssertEqual(classify([menu, app(visible)]).context, .desktop)
  }

  /// More windows, duplicates and any order can only suppress the effect, never allow it.
  func testExtraDuplicateAndReorderedWindowsNeverAllowMore() {
    var seed: UInt64 = 42
    func next(_ bound: Int) -> Int {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return Int((seed >> 33) % UInt64(bound))
    }
    func random() -> MenuBarEvidence.Window {
      let owner = [MenuBarEvidence.Owner.windowServer, .desktop, .ownApp, .application][next(4)]
      let layer = [-2_147_483_622, -1, 0, 3, 24, 25, 26, 27, 1000][next(9)]
      let x = CGFloat([-100, 0, 60, 700, 1512][next(5)])
      let y = CGFloat([-50, 0, 2, 60, 948, 949][next(6)])
      let width = CGFloat([0, 30, 600, 756, 1452, 1512, 3000][next(7)])
      let height = CGFloat([0, 33, 34, 888, 949, 982, 2000][next(7)])
      return .init(owner: owner, layer: layer, bounds: CGRect(x: x, y: y, width: width, height: height))
    }
    for _ in 0..<2000 {
      var windows = (0..<next(6)).map { _ in random() }
      let base = classify(windows)
      windows.append(random())
      if let first = windows.first { windows.append(first) }
      windows.reverse()
      let more = classify(windows)
      if base.context == .fullScreen { XCTAssertEqual(more.context, .fullScreen) }
      if base.menuVisible { XCTAssertTrue(more.menuVisible) }
      XCTAssertNotEqual(more.context, .unknown)
    }
  }

  // MARK: - Window list dictionaries

  private func entry(owner: Any? = "Safari", pid: Any? = Int32(500), layer: Any? = 0,
                     bounds: Any? = ["X": 0, "Y": 33, "Width": 1512, "Height": 949]) -> [String: Any] {
    var result: [String: Any] = ["kCGWindowAlpha": 1, "kCGWindowNumber": 77, "extra": "ignored"]
    result[kCGWindowOwnerName as String] = owner
    result[kCGWindowOwnerPID as String] = pid
    result[kCGWindowLayer as String] = layer
    result[kCGWindowBounds as String] = bounds
    return result
  }

  private func parse(_ list: [[String: Any]]) -> [MenuBarEvidence.Window]? {
    MenuBarEvidence.windows(from: list, ownPID: 42, primaryScreenHeight: 982)
  }

  func testWindowListOwnersLayersAndTheFlippedAxis() throws {
    let list = [
      entry(owner: "Window Server", layer: 24, bounds: ["X": 0, "Y": 0, "Width": 1512, "Height": 33]),
      entry(owner: "Dock", layer: 20), entry(owner: "Finder", layer: -2_147_483_603),
      entry(owner: "Finder", layer: 0), entry(owner: "Anything", pid: Int32(42)),
      entry(owner: "Window Server", pid: Int32(42)), entry(owner: nil), entry(), entry(),
    ]
    let windows = try XCTUnwrap(parse(list))
    XCTAssertEqual(windows.map(\.owner),
                   [.windowServer, .desktop, .desktop, .application, .ownApp, .ownApp,
                    .application, .application, .application])
    XCTAssertEqual(windows.map(\.layer), [24, 20, -2_147_483_603, 0, 0, 0, 0, 0, 0])
    XCTAssertEqual(windows[0].bounds, CGRect(x: 0, y: 949, width: 1512, height: 33))
    XCTAssertEqual(windows[7].bounds, CGRect(x: 0, y: 0, width: 1512, height: 949))
    XCTAssertEqual(parse([])?.count, 0)
    XCTAssertTrue(MenuBarEvidence.evaluate(frame: frame, visibleFrame: visible,
                                           bandFrame: CGRect(x: 0, y: 949, width: 1512, height: 33),
                                           windows: windows).menuVisible)
  }

  private let menuEntryBounds: [String: Any] = ["X": 0, "Y": 0, "Width": 1512, "Height": 34]
  private let fullScreenBounds: [String: Any] = ["X": 0, "Y": 0, "Width": 1512, "Height": 982]

  /// Show Desktop and a click on the wallpaper add a full-screen WindowManager window at
  /// layer 18; the screenshot and recording tool adds a full-screen Screenshot window at layer 24.
  func testShowDesktopAndScreenshotWindowsAreNotFullScreenEvidence() throws {
    for (owner, layer) in [("WindowManager", 18), ("Screenshot", 24)] {
      let list = [
        entry(owner: "Window Server", layer: 24, bounds: menuEntryBounds),
        entry(owner: owner, pid: Int32(600), layer: layer, bounds: fullScreenBounds)
      ]
      let result = MenuBarEvidence.evaluate(frame: frame, visibleFrame: visible, bandFrame: strip,
                                            windows: try XCTUnwrap(parse(list)))
      XCTAssertEqual(result.context, .desktop, owner)
      XCTAssertTrue(result.menuVisible, owner)
    }
  }

  func testWindowManagerAndScreenshotWindowsAreClassifiedAsDesktop() throws {
    for owner in ["WindowManager", "Screenshot"] {
      for layer in [-1, 0, 18, 24, 26] {
        let windows = try XCTUnwrap(parse([
          entry(owner: owner, pid: Int32(600), layer: layer, bounds: fullScreenBounds)
        ]))
        XCTAssertEqual(windows.map(\.owner), [.desktop], "\(owner) layer \(layer)")
      }
    }
  }

  func testARealFullScreenAppIsStillFullScreenEvidence() throws {
    for owner in ["Safari", "Windowmanager", "WindowManagerHelper", "Screenshots", "Finder"] {
      let list = [
        entry(owner: "Window Server", layer: 24, bounds: menuEntryBounds),
        entry(owner: owner, pid: Int32(700), layer: 0, bounds: fullScreenBounds)
      ]
      let result = MenuBarEvidence.evaluate(frame: frame, visibleFrame: visible, bandFrame: strip,
                                            windows: try XCTUnwrap(parse(list)))
      XCTAssertEqual(result.context, .fullScreen, owner)
      XCTAssertTrue(result.menuVisible, owner)
    }
  }

  func testAnIncompleteOrMistypedWindowMakesTheListUnavailable() {
    let malformed: [[String: Any]] = [
      entry(pid: nil), entry(layer: nil), entry(bounds: nil),
      entry(owner: 7), entry(owner: ["Safari"]), entry(pid: "500"), entry(layer: "0"),
      entry(layer: [0]), entry(bounds: "0,0,10,10"), entry(bounds: [0, 0, 10, 10]),
      entry(bounds: ["X": 0, "Y": 0, "Width": 10]), entry(bounds: ["X": 0, "Y": 0]),
      entry(bounds: [String: Any]()), entry(bounds: ["X": "a", "Y": 0, "Width": 1, "Height": 1]),
      entry(bounds: ["X": 0, "Y": 0, "Width": Double.infinity, "Height": 1]),
      entry(bounds: ["X": Double.nan, "Y": 0, "Width": 1, "Height": 1]),
      [:],
    ]
    for (index, bad) in malformed.enumerated() {
      XCTAssertNil(parse([bad]), "case \(index)")
      XCTAssertNil(parse([entry(), bad, entry()]), "case \(index) between good windows")
      XCTAssertNil(parse([entry(), entry(), bad]), "case \(index) last")
    }
    for height in [CGFloat(0), -982, .nan, .infinity] {
      XCTAssertNil(MenuBarEvidence.windows(from: [entry()], ownPID: 42, primaryScreenHeight: height))
    }
  }
}

// MARK: - Revealed desktop

extension MenuBarEvidenceTests {
  private func windowManager(layer: Int, bounds: [String: Any]) -> [String: Any] {
    entry(owner: "WindowManager", pid: Int32(600), layer: layer, bounds: bounds)
  }

  /// The menu bar and the two WindowManager windows at negative layers of every real list.
  private func revealed(_ extra: [[String: Any]], frame: CGRect? = nil) -> Bool {
    let list = [
      entry(owner: "Window Server", layer: 24, bounds: menuEntryBounds),
      windowManager(layer: -2_147_483_624, bounds: fullScreenBounds),
      windowManager(layer: -2_147_483_622, bounds: fullScreenBounds)
    ] + extra
    return MenuBarEvidence.evaluate(frame: frame ?? self.frame, visibleFrame: visible,
                                    bandFrame: strip, windows: parse(list)).desktopRevealed
  }

  func testAFullScreenWindowManagerWindowRevealsTheDesktop() {
    XCTAssertTrue(revealed([windowManager(layer: 18, bounds: fullScreenBounds)]))
    for layer in [0, 16, 18, 24] {
      for bounds: [String: Any] in [
        ["X": 0, "Y": 0, "Width": 1361, "Height": 982], ["X": 151, "Y": 0, "Width": 1361, "Height": 982],
        ["X": 0, "Y": 2, "Width": 1512, "Height": 978], ["X": -10, "Y": -10, "Width": 1600, "Height": 1100]
      ] {
        XCTAssertTrue(revealed([windowManager(layer: layer, bounds: bounds)]), "layer \(layer) \(bounds)")
      }
    }
    // The revealed desktop is still the desktop.
    let list = [
      entry(owner: "Window Server", layer: 24, bounds: menuEntryBounds),
      windowManager(layer: 18, bounds: fullScreenBounds)
    ]
    let result = MenuBarEvidence.evaluate(frame: frame, visibleFrame: visible, bandFrame: strip,
                                          windows: parse(list))
    XCTAssertEqual(result.context, .desktop)
    XCTAssertTrue(result.menuVisible)
  }

  func testMalformedNumbersInvalidateTheWholeListInEveryPosition() {
    let good = windowManager(layer: 18, bounds: fullScreenBounds)
    let pid = kCGWindowOwnerPID as String
    let layer = kCGWindowLayer as String
    let alpha = kCGWindowAlpha as String
    let bounds = kCGWindowBounds as String
    let invalid: [Any?] = [nil, true, "1", [1], NSNull(), Double.nan, Double.infinity]
    var malformed: [[String: Any]] = []
    for key in [pid, layer, alpha] {
      for value in invalid {
        var row = good
        row[key] = value
        malformed.append(row)
      }
    }
    for key in ["X", "Y", "Width", "Height"] {
      for value in invalid {
        var row = fullScreenBounds
        row[key] = value
        malformed.append(windowManager(layer: 18, bounds: row))
      }
    }
    let outsideInt32: [Any] = [Int64(Int32.min) - 1, Int64(Int32.max) + 1, 18.5]
    let outOfRange: [(String, [Any])] = [
      (pid, outsideInt32 + [0, -1, Int64(4_294_967_338)]),
      (layer, outsideInt32), (alpha, [-0.01, 1.01])
    ]
    for (key, values) in outOfRange {
      for value in values {
        var row = good
        row[key] = value
        malformed.append(row)
      }
    }
    let huge = Double.greatestFiniteMagnitude
    for rect in [
      ["X": 1512, "Y": 0, "Width": -1512, "Height": 982],
      ["X": 0, "Y": 982, "Width": 1512, "Height": -982],
      ["X": huge, "Y": 0, "Width": huge, "Height": 982],
      ["X": 0, "Y": huge, "Width": 1512, "Height": huge]
    ] as [[String: Any]] {
      var row = good
      row[bounds] = rect
      malformed.append(row)
    }
    for row in malformed {
      for index in 0...2 {
        var list = [good, good]
        list.insert(row, at: index)
        XCTAssertNil(parse(list))
        XCTAssertFalse(revealed(list))
      }
    }
  }

  func testRevealIsInvariantUnderDuplicatesAndOrdering() {
    let candidates = [
      windowManager(layer: -1, bounds: fullScreenBounds),
      windowManager(layer: 16, bounds: ["X": 0, "Y": 0, "Width": 77, "Height": 70])
    ]
    for alpha in [0.0, 0.01, 0.5, 1.0] {
      var full = windowManager(layer: 18, bounds: fullScreenBounds)
      full[kCGWindowAlpha as String] = alpha
      full["unknown"] = ["ignored": true]
      for index in 0...candidates.count {
        var rows = candidates
        rows.insert(full, at: index)
        XCTAssertEqual(revealed(rows), alpha > 0)
        XCTAssertEqual(revealed(Array(rows.reversed()) + rows), alpha > 0)
      }
    }
  }

  func testOtherWindowsDoNotRevealTheDesktop() {
    XCTAssertFalse(revealed([]))
    for extra in [
      windowManager(layer: 16, bounds: ["X": 1400, "Y": 900, "Width": 77, "Height": 70]),
      windowManager(layer: -1, bounds: fullScreenBounds),
      windowManager(layer: 18, bounds: ["X": 0, "Y": 0, "Width": 1360, "Height": 982]),
      windowManager(layer: 18, bounds: ["X": 0, "Y": 3, "Width": 1512, "Height": 979]),
      windowManager(layer: 18, bounds: ["X": 0, "Y": 0, "Width": 1512, "Height": 979]),
      windowManager(layer: 18, bounds: ["X": 1512, "Y": 0, "Width": 1920, "Height": 1080]),
      windowManager(layer: 18, bounds: ["X": 0, "Y": 0, "Width": 0, "Height": 982]),
      entry(owner: "Screenshot", pid: Int32(601), layer: 24, bounds: fullScreenBounds),
      entry(owner: "Dock", pid: Int32(602), layer: 18, bounds: fullScreenBounds),
      entry(owner: "Safari", pid: Int32(603), layer: 18, bounds: fullScreenBounds),
      entry(owner: nil, pid: Int32(604), layer: 18, bounds: fullScreenBounds),
      entry(owner: "WindowManager", pid: Int32(42), layer: 18, bounds: fullScreenBounds)
    ] {
      XCTAssertFalse(revealed([extra]), "\(extra)")
    }
    let full = windowManager(layer: 18, bounds: fullScreenBounds)
    XCTAssertFalse(revealed([full], frame: .null))
    XCTAssertFalse(revealed([full, entry(pid: nil)]))
    XCTAssertFalse(MenuBarEvidence.evaluate(frame: frame, visibleFrame: visible, bandFrame: strip,
                                            windows: nil).desktopRevealed)
  }
}
