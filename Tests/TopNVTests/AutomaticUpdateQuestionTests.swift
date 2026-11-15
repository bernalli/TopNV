import AppKit
import TopNVCore
import XCTest

@testable import TopNV

/// The first-launch question, presented as in MonoPods: a window without a modal session.
@MainActor
final class AutomaticUpdateQuestionTests: XCTestCase {
  private var presented: [(window: NSWindow, activate: Bool)] = []
  private var answers: [AutomaticUpdateAnswer] = []

  private func makeQuestion() -> AutomaticUpdateQuestion {
    AutomaticUpdateQuestion(
      localizer: Localizer(bundle: .main),
      present: { [weak self] in self?.presented.append((window: $0, activate: $1)) },
      reply: { [weak self] in self?.answers.append($0) })
  }

  private func click(_ button: NSButton) {
    guard let action = button.action else { return }
    NSApplication.shared.sendAction(action, to: button.target, from: button)
  }

  func testTheQuestionAsksWithTwoButtonsAndActivatesWithoutAModalSession() {
    let question = makeQuestion()
    question.show()
    defer { click(question.alert.buttons[1]) }
    let alert = question.alert
    XCTAssertEqual(alert.messageText, "Check for Updates Automatically?")
    XCTAssertEqual(
      alert.informativeText,
      "TopNV can check for new versions once a day. You can change this at any time in Options.")
    XCTAssertEqual(alert.buttons.map(\.title), ["Check Automatically", "Don't Check"])
    XCTAssertEqual(alert.buttons[0].keyEquivalent, "\r")
    XCTAssertEqual(alert.buttons[1].keyEquivalent, "\u{1b}")
    XCTAssertEqual(presented.count, 1)
    XCTAssertTrue(presented.first?.window === alert.window)
    XCTAssertEqual(presented.first?.activate, true)
    XCTAssertNil(NSApplication.shared.modalWindow)
    XCTAssertTrue(answers.isEmpty)
  }

  func testOnlyTheFirstClickAnswers() {
    for (button, answer) in [(0, AutomaticUpdateAnswer.enable), (1, .decline)] {
      answers = []
      let question = makeQuestion()
      question.show()
      let buttons = question.alert.buttons
      click(buttons[button])
      XCTAssertEqual(answers, [answer])
      click(buttons[0])
      click(buttons[1])
      XCTAssertEqual(answers, [answer])
      XCTAssertFalse(question.alert.window.isVisible)
    }
  }

  func testTheQuestionKeepsItselfAliveUntilTheAnswer() throws {
    weak var shown: AutomaticUpdateQuestion?
    var buttons: [NSButton] = []
    do {
      let question = makeQuestion()
      question.show()
      shown = question
      buttons = question.alert.buttons
    }
    XCTAssertNotNil(shown)
    click(try XCTUnwrap(buttons.last))
    XCTAssertEqual(answers, [.decline])
    XCTAssertNil(shown)
  }

  func testOnlyTheFirstButtonEnables() {
    XCTAssertEqual(AutomaticUpdateQuestion.answer(buttonIndex: 0), .enable)
    XCTAssertEqual(AutomaticUpdateQuestion.answer(buttonIndex: 1), .decline)
    XCTAssertEqual(AutomaticUpdateQuestion.answer(buttonIndex: 2), .dismissed)
    XCTAssertEqual(AutomaticUpdateQuestion.answer(buttonIndex: nil), .dismissed)
  }
}
