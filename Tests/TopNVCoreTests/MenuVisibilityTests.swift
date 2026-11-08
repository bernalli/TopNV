import Combine
import XCTest

@testable import TopNVCore

final class MenuVisibilityTests: XCTestCase {
  @MainActor
  func testHideAndReopenPersistAcrossInstances() throws {
    let suite = "MenuVisibilityTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = MenuVisibility(defaults: defaults, key: "showMenuBarIcon")
    XCTAssertTrue(model.isVisible)
    model.setMenuVisible(false)
    XCTAssertFalse(model.isVisible)
    XCTAssertFalse(MenuVisibility(defaults: defaults, key: "showMenuBarIcon").isVisible)
    model.setMenuVisible(true)
    XCTAssertTrue(MenuVisibility(defaults: defaults, key: "showMenuBarIcon").isVisible)
  }

  @MainActor
  func testSceneWriteBackIsDeferredAndEqualValuesDoNotPublish() throws {
    let suite = "MenuVisibilityTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var pending: [@MainActor () -> Void] = []
    let model = MenuVisibility(defaults: defaults, key: "showMenuBarIcon", schedule: {
      pending.append($0)
    })
    var publications = 0
    let subscription = model.objectWillChange.sink { publications += 1 }
    defer { subscription.cancel() }
    model.requestMenuVisible(true)
    model.setMenuVisible(true)
    XCTAssertEqual(publications, 0)
    XCTAssertTrue(pending.isEmpty)
    model.requestMenuVisible(false)
    XCTAssertTrue(model.isVisible)
    XCTAssertEqual(publications, 0)
    XCTAssertNil(defaults.object(forKey: "showMenuBarIcon"))
    try XCTUnwrap(pending.first)()
    XCTAssertFalse(model.isVisible)
    XCTAssertEqual(publications, 1)
    XCTAssertEqual(defaults.object(forKey: "showMenuBarIcon") as? Bool, false)
  }

  @MainActor
  func testReopenCancelsAnOlderDeferredHideEvenWhenAlreadyVisible() throws {
    let suite = "MenuVisibilityTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var pending: [@MainActor () -> Void] = []
    let model = MenuVisibility(defaults: defaults, key: "showMenuBarIcon", schedule: {
      pending.append($0)
    })
    model.requestMenuVisible(false)
    model.setMenuVisible(true)
    try XCTUnwrap(pending.first)()
    XCTAssertTrue(model.isVisible)
  }

  @MainActor
  func testLatestSceneRequestCancelsAnOlderDifferentValue() throws {
    let suite = "MenuVisibilityTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var pending: [@MainActor () -> Void] = []
    let model = MenuVisibility(defaults: defaults, key: "showMenuBarIcon", schedule: {
      pending.append($0)
    })
    model.setMenuVisible(false)
    model.requestMenuVisible(true)
    model.requestMenuVisible(false)
    try XCTUnwrap(pending.first)()
    XCTAssertFalse(model.isVisible)
    XCTAssertFalse(defaults.bool(forKey: "showMenuBarIcon"))
  }
}
