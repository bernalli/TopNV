import AppKit
import XCTest
@testable import TopNV

final class UpdateIntegrationTests: XCTestCase {
  @MainActor func testQuestionOnlyEnablesForExplicitFirstButton() {
    XCTAssertEqual(AutomaticUpdateQuestion.answer(for: .alertFirstButtonReturn), .enable)
    XCTAssertEqual(AutomaticUpdateQuestion.answer(for: .alertSecondButtonReturn), .decline)
    XCTAssertEqual(AutomaticUpdateQuestion.answer(for: .abort), .dismissed)
    XCTAssertEqual(AutomaticUpdateQuestion.answer(for: .cancel), .dismissed)
  }
}
