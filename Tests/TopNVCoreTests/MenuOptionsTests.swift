import XCTest

@testable import TopNVCore

final class MenuOptionsTests: XCTestCase {
  func testPresets() {
    XCTAssertEqual(CornerRadiusOption.presets, [5, 10, 15, 20, 25, 30])
  }

  func testEveryWholeRadiusHasExactlyOneMatchingRow() {
    for radius in 0...30 {
      let value = Double(radius)
      let options = CornerRadiusOption.options(for: value)
      let isPreset = [5, 10, 15, 20, 25, 30].contains(radius)
      XCTAssertEqual(options.map(\.value).prefix(6), [5, 10, 15, 20, 25, 30])
      XCTAssertEqual(options.count, isPreset ? 6 : 7, "Radius \(radius)")
      XCTAssertEqual(Set(options.map(\.id)).count, options.count)
      let selected = options.filter { $0.value == value }
      XCTAssertEqual(selected.count, 1, "Radius \(radius)")
      XCTAssertEqual(selected.first?.isCustom, !isPreset)
      XCTAssertEqual(
        selected.first?.title, isPreset ? "\(radius) pt" : "Custom (\(radius) pt)")
      XCTAssertEqual(options.filter(\.isCustom).count, isPreset ? 0 : 1)
    }
  }

  func testFractionalRadiiAreNotRoundedToPresets() {
    let values = (0..<30).map { Double($0) + 0.5 }
      + [Double(5).nextDown, Double(5).nextUp, 13.25, 29.999]
    for value in values {
      let options = CornerRadiusOption.options(for: value)
      XCTAssertEqual(options.count, 7)
      XCTAssertEqual(options.filter { $0.value == value }.count, 1)
      XCTAssertEqual(options.last?.value, value)
      XCTAssertEqual(options.last?.isCustom, true)
      XCTAssertEqual(options.last?.title, "Custom (\(value) pt)")
    }
  }

  func testOutOfRangeRadiiRemainCustomWithoutClamping() {
    for value: Double in [-100, -1, -0.5, 30.5, 31, 100] {
      let options = CornerRadiusOption.options(for: value)
      XCTAssertEqual(options.count, 7)
      XCTAssertEqual(options.filter { $0.value == value }.count, 1)
      XCTAssertEqual(options.last?.value, value)
      XCTAssertEqual(options.last?.isCustom, true)
    }
  }

  func testCustomRowDisappearsWhenAPresetIsSelected() {
    XCTAssertEqual(CornerRadiusOption.options(for: 13).last?.title, "Custom (13 pt)")
    XCTAssertFalse(CornerRadiusOption.options(for: 15).contains(where: \.isCustom))
  }

  func testGitHubLinks() throws {
    let paths: [AppLink: String] = [
      .help: "/bernalli/topNV/blob/main/README.md",
      .releaseNotes: "/bernalli/topNV/releases",
      .reportIssue: "/bernalli/topNV/issues/new",
      .source: "/bernalli/topNV",
    ]
    XCTAssertEqual(AppLink.allCases.count, 4)
    for link in AppLink.allCases {
      let url = try XCTUnwrap(link.url)
      XCTAssertEqual(url.scheme, "https")
      XCTAssertEqual(url.host, "github.com")
      XCTAssertEqual(url.path, paths[link])
      XCTAssertNil(url.user)
      XCTAssertNil(url.password)
      XCTAssertNil(url.query)
      XCTAssertNil(url.fragment)
    }
  }
}
