import AppKit
import TopNVCore
import XCTest

@testable import TopNV

private func row(_ id: String, _ title: String, _ kind: MenuRow.Kind, symbol: String? = nil)
  -> MenuRow
{
  MenuRow(id: id, title: title, symbol: symbol, kind: kind)
}

@MainActor
final class MenuRendererTests: XCTestCase {
  private func renderer(
    _ style: InfoRowStyle, perform: @escaping (MenuCommand) -> Void = { _ in }
  ) -> MenuRenderer {
    MenuRenderer(metrics: .fallback, infoStyle: style, perform: perform)
  }

  func testHeaderRowBecomesTheNativeSectionHeader() throws {
    let menu = NSMenu()
    renderer(.secondaryView).apply([row("topnv", "TopNV", .header)], to: menu)
    let item = try XCTUnwrap(menu.items.first)
    XCTAssertTrue(item.isSectionHeader)
    XCTAssertEqual(item.title, "TopNV")
  }

  /// AppKit dims disabled items; the view draws the text in the secondary label color instead.
  func testInformationRowsAreUnselectableViewsInTheSecondaryLabelColor() throws {
    let menu = NSMenu()
    renderer(.secondaryView).apply(
      [row("status.0", "Notch Hidden, Corners Rounded", .info, symbol: "display")], to: menu)
    XCTAssertFalse(menu.autoenablesItems)
    let item = try XCTUnwrap(menu.items.first)
    XCTAssertFalse(item.isEnabled)
    XCTAssertNil(item.action)
    XCTAssertNil(item.image)
    let view = try XCTUnwrap(item.view as? InfoRowView)
    XCTAssertEqual(view.label.stringValue, "Notch Hidden, Corners Rounded")
    XCTAssertEqual(view.label.textColor, NSColor.secondaryLabelColor)
    XCTAssertEqual(view.symbolView.contentTintColor, NSColor.secondaryLabelColor)
    XCTAssertFalse(view.symbolView.isHidden)
    XCTAssertEqual(view.frame.height, MenuMetrics.fallback.rowHeight)
  }

  func testInformationRowsBeforeMacOS27AreDisabledNativeItems() throws {
    let menu = NSMenu()
    renderer(.disabledItem).apply(
      [
        row("status.0", "Inactive", .info, symbol: "power"),
        row("version.0", "Version 1.2.0", .info),
      ], to: menu)
    XCTAssertFalse(menu.autoenablesItems)
    for item in menu.items {
      XCTAssertFalse(item.isEnabled)
      XCTAssertNil(item.action)
      XCTAssertNil(item.view)
    }
    XCTAssertEqual(menu.items.map(\.title), ["Inactive", "Version 1.2.0"])
    XCTAssertNotNil(menu.items[0].image)
    XCTAssertNil(menu.items[1].image)
  }

  func testTogglesShowStateAndEnabling() {
    let menu = NSMenu()
    renderer(.secondaryView).apply(
      [
        row(
          "cornersOnAllDisplays", "Corners on All Displays",
          .toggle(.cornersOnAllDisplays, isOn: true, enabled: false), symbol: "display.2"),
        row("hideNotch", "Hide Notch", .toggle(.hideNotch, isOn: false, enabled: true)),
      ], to: menu)
    XCTAssertEqual(menu.items[0].state, .on)
    XCTAssertFalse(menu.items[0].isEnabled)
    XCTAssertNotNil(menu.items[0].image)
    XCTAssertEqual(menu.items[1].state, .off)
    XCTAssertTrue(menu.items[1].isEnabled)
  }

  func testASubmenuCanBeDisabled() throws {
    let menu = NSMenu()
    renderer(.secondaryView).apply(
      [
        row("details", "Details", .submenu([row("a.0", "A", .info)], enabled: false)),
        row("options", "Options", .submenu([], enabled: true)),
      ], to: menu)
    XCTAssertFalse(menu.items[0].isEnabled)
    XCTAssertNotNil(menu.items[0].submenu)
    XCTAssertTrue(menu.items[1].isEnabled)
  }

  func testANewStateUpdatesTheSameItemsInPlace() throws {
    let renderer = renderer(.secondaryView)
    let menu = NSMenu()
    func rows(on: Bool, display: String, caption: Bool) -> [MenuRow] {
      var rows = [row("topnv", "TopNV", .header)]
      rows.append(row("hideNotch", "Hide Notch", .toggle(.hideNotch, isOn: on, enabled: true)))
      if caption { rows.append(row("caption.0", "Caption", .info)) }
      rows.append(
        row("details", "Details", .submenu([row("display.0", display, .info)], enabled: true)))
      return rows
    }
    renderer.apply(rows(on: true, display: "Applies to: Built-in Display", caption: true), to: menu)
    let toggle = menu.items[1]
    let details = try XCTUnwrap(menu.items.first { $0.title == "Details" })
    let submenu = try XCTUnwrap(details.submenu)
    let display = try XCTUnwrap(submenu.items.first)
    let view = try XCTUnwrap(display.view as? InfoRowView)

    renderer.apply(rows(on: false, display: "Applies to: All Displays", caption: false), to: menu)

    XCTAssertEqual(menu.items.map(\.title), ["TopNV", "Hide Notch", "Details"])
    XCTAssertTrue(menu.items[1] === toggle)
    XCTAssertEqual(toggle.state, .off)
    XCTAssertTrue(menu.items[2] === details)
    XCTAssertTrue(details.submenu === submenu)
    XCTAssertTrue(submenu.items[0] === display)
    XCTAssertTrue(display.view === view)
    XCTAssertEqual(view.label.stringValue, "Applies to: All Displays")
    XCTAssertEqual(display.title, "Applies to: All Displays")
  }

  func testRowsThatDisappearAreRemoved() {
    let renderer = renderer(.disabledItem)
    let menu = NSMenu()
    renderer.apply(
      [
        row("version.0", "Version", .info),
        row("check", "Check for Updates…", .action(.checkForUpdates, enabled: true, key: "")),
        row("about", "About TopNV", .action(.about, enabled: true, key: "")),
      ], to: menu)
    renderer.apply(
      [
        row("version.0", "Version", .info),
        row("about", "About TopNV", .action(.about, enabled: true, key: "")),
      ], to: menu)
    XCTAssertEqual(menu.items.map(\.title), ["Version", "About TopNV"])
  }

  func testSelectingAnItemPerformsItsCommand() {
    var performed: [MenuCommand] = []
    let renderer = renderer(.secondaryView) { performed.append($0) }
    let menu = NSMenu()
    renderer.apply(
      [
        row("hideNotch", "Hide Notch", .toggle(.hideNotch, isOn: true, enabled: true)),
        row("check", "Check for Updates…", .action(.checkForUpdates, enabled: false, key: "")),
        row("report", "Report an Issue…", .action(.reportIssue, enabled: true, key: "")),
        row("quit", "Quit TopNV", .action(.quit, enabled: true, key: "q")),
      ], to: menu)
    XCTAssertFalse(menu.items[1].isEnabled)
    XCTAssertEqual(menu.items[3].keyEquivalent, "q")
    XCTAssertEqual(menu.items[3].keyEquivalentModifierMask, .command)
    // Items hold their target weakly; the action goes to the item's own target.
    withExtendedLifetime(renderer) {
      for index in [0, 2, 3] {
        let item = menu.items[index]
        XCTAssertTrue(item.target === renderer)
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
      }
    }
    XCTAssertEqual(performed, [.hideNotch, .reportIssue, .quit])
  }

  /// For every state of the menu and both styles, no information row can be chosen.
  func testInformationRowsAreNeverSelectableInAnyMenuState() {
    let localizer = Localizer(bundle: .main)
    for style in InfoRowStyle.allCases {
      let renderer = renderer(style)
      let menu = NSMenu()
      let updateStates: [UpdateItems] = [
        .hidden, .waiting, .ready(canCheck: true, checksAutomatically: true),
        .ready(canCheck: false, checksAutomatically: false),
      ]
      for mask in 0..<(1 << 5) {
        func bit(_ index: Int) -> Bool { mask & (1 << index) != 0 }
        for updates in updateStates {
          for error in [nil, "Operation not permitted."] as [String?] {
            let state = MenuState(
              hideNotch: bit(0), roundCorners: bit(1), cornersOnAllDisplays: bit(2),
              launchAtLogin: bit(3), loginNeedsApproval: bit(4), loginError: error,
              updates: updates)
            let rows = MenuLayout.rows(for: state, localizer: localizer)
            renderer.apply(rows, to: menu)
            for (item, row) in zip(Self.items(of: menu), Self.flatten(rows)) where row.kind == .info {
              XCTAssertFalse(item.isEnabled, "\(row.id) \(mask)")
              XCTAssertNil(item.action, "\(row.id) \(mask)")
              XCTAssertEqual(item.view is InfoRowView, style == .secondaryView, row.id)
            }
            XCTAssertEqual(Self.items(of: menu).count, Self.flatten(rows).count)
          }
        }
      }
    }
  }

  private static func items(of menu: NSMenu) -> [NSMenuItem] {
    menu.items.flatMap { item in [item] + (item.submenu.map { items(of: $0) } ?? []) }
  }

  private static func flatten(_ rows: [MenuRow]) -> [MenuRow] {
    rows.flatMap { row -> [MenuRow] in
      if case .submenu(let children, _) = row.kind { return [row] + flatten(children) }
      return [row]
    }
  }
}
