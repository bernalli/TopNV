import XCTest

@testable import TopNVCore

final class AppLinkTests: XCTestCase {
  func testGitHubLinks() throws {
    let paths: [AppLink: String] = [
      .reportIssue: "/bernalli/TopNV/issues/new",
      .source: "/bernalli/TopNV",
      .sponsor: "/sponsors/bernalli",
    ]
    XCTAssertEqual(AppLink.allCases.count, 3)
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
