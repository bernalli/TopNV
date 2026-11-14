import Foundation
import XCTest

@testable import TopNVCore

/// A problem found in the raw text of a `Localizable.strings` table.
enum TableProblem: Hashable {
  case byteOrderMark
  case missingFinalNewline
  case malformedLine(Int)
  case unexpectedComment(Int)
  case unsorted(Int)
  case duplicateKey(String)
  case missingKey(String)
  case extraKey(String)
  case emptyValue(String)
  case invalidPlaceholders(String)
  case placeholderMismatch(String)
  case missingMarker(String)
  case unexpectedMarker(String)
  case sharedValueChanged(String)
}

/// What a table must contain for one key.
struct BaseKey {
  let isShared: Bool
  let value: String
}

let pendingMarker = "/* PENDING-MONOPODS */"

struct ParsedEntry {
  let line: Int
  let key: String
  let value: String
  let hasMarker: Bool
}

private let entryPattern = try! NSRegularExpression(
  pattern: #"^(/\* PENDING-MONOPODS \*/ )?"((?:[^"\\]|\\.)*)" = "((?:[^"\\]|\\.)*)";$"#)

private func unescape(_ text: String) -> String {
  var result = ""
  var escaping = false
  for character in text {
    if escaping {
      result.append(character == "n" ? "\n" : character)
      escaping = false
    } else if character == "\\" {
      escaping = true
    } else {
      result.append(character)
    }
  }
  return result
}

/// Parses the shared format: UTF-8 without BOM, one `"key" = "value";` per line, lines sorted
/// by UTF-8 bytes (ignoring the marker), no comments except the leading pending marker.
func parseTable(_ raw: String) -> (entries: [ParsedEntry], problems: [TableProblem]) {
  var problems: [TableProblem] = []
  var text = raw
  if text.unicodeScalars.first == "\u{FEFF}" {
    problems.append(.byteOrderMark)
    text = String(String.UnicodeScalarView(text.unicodeScalars.dropFirst()))
  }
  var lines = text.components(separatedBy: "\n")
  if lines.last == "" {
    lines.removeLast()
  } else {
    problems.append(.missingFinalNewline)
  }
  var entries: [ParsedEntry] = []
  var previous: [UInt8]?
  for (offset, line) in lines.enumerated() {
    let number = offset + 1
    let range = NSRange(line.startIndex..., in: line)
    guard let match = entryPattern.firstMatch(in: line, range: range),
      let keyRange = Range(match.range(at: 2), in: line),
      let valueRange = Range(match.range(at: 3), in: line)
    else {
      problems.append(
        line.contains("/*") || line.contains("//")
          ? .unexpectedComment(number) : .malformedLine(number))
      continue
    }
    let hasMarker = match.range(at: 1).location != NSNotFound
    let sortable = Array((hasMarker ? String(line.dropFirst(pendingMarker.count + 1)) : line).utf8)
    if let previous, previous.lexicographicallyPrecedes(sortable) == false, previous != sortable {
      problems.append(.unsorted(number))
    }
    previous = sortable
    entries.append(
      ParsedEntry(
        line: number, key: unescape(String(line[keyRange])),
        value: unescape(String(line[valueRange])),
        hasMarker: hasMarker))
  }
  return (entries, problems)
}

/// Argument types in argument order, plus the number of literal percent signs; nil when the
/// placeholders are malformed (unknown conversion, mixed styles, skipped or repeated index).
func placeholderSignature(_ text: String) -> (types: [Character], percents: Int)? {
  var sequential: [Character] = []
  var positional: [Int: Character] = [:]
  var percents = 0
  var characters = Array(text)[...]
  while let character = characters.popFirst() {
    guard character == "%" else { continue }
    var digits = ""
    while let next = characters.first, next.isASCII, next.isNumber {
      digits.append(next)
      characters.removeFirst()
    }
    if !digits.isEmpty {
      guard characters.popFirst() == "$", let type = characters.popFirst(),
        type == "@" || type == "d",
        let index = Int(digits), index > 0, positional[index] == nil
      else { return nil }
      positional[index] = type
      continue
    }
    switch characters.popFirst() {
    case "%": percents += 1
    case "@": sequential.append("@")
    case "d": sequential.append("d")
    default: return nil
    }
  }
  if !positional.isEmpty {
    guard sequential.isEmpty, Set(positional.keys) == Set(1...positional.count) else { return nil }
    return ((1...positional.count).map { positional[$0]! }, percents)
  }
  return (sequential, percents)
}

func tableProblems(base: [String: BaseKey], raw: String) -> [TableProblem] {
  let parsed = parseTable(raw)
  var problems = parsed.problems
  var seen: Set<String> = []
  for entry in parsed.entries {
    guard seen.insert(entry.key).inserted else {
      problems.append(.duplicateKey(entry.key))
      continue
    }
    guard let expected = base[entry.key] else {
      problems.append(.extraKey(entry.key))
      continue
    }
    if entry.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      problems.append(.emptyValue(entry.key))
    }
    if let keySignature = placeholderSignature(entry.key),
      let valueSignature = placeholderSignature(entry.value)
    {
      if keySignature.types != valueSignature.types
        || keySignature.percents != valueSignature.percents
      {
        problems.append(.placeholderMismatch(entry.key))
      }
    } else {
      problems.append(.invalidPlaceholders(entry.key))
    }
    if expected.isShared {
      if !entry.hasMarker { problems.append(.missingMarker(entry.key)) }
      if entry.value != expected.value { problems.append(.sharedValueChanged(entry.key)) }
    } else if entry.hasMarker {
      problems.append(.unexpectedMarker(entry.key))
    }
  }
  for key in base.keys.sorted() where !seen.contains(key) {
    problems.append(.missingKey(key))
  }
  return problems
}

final class LocalizationTests: XCTestCase {
  private static let languages = ["en", "it", "es", "fr", "de", "pt-BR", "ja", "zh-Hans"]
  private static let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  private static let localization = repository.appendingPathComponent("Localization")

  private static var textKeyBase: [String: BaseKey] {
    Dictionary(
      uniqueKeysWithValues: TextKey.allCases.map {
        ($0.rawValue, BaseKey(isShared: $0.isShared, value: $0.rawValue))
      })
  }

  private func tableData(_ language: String) throws -> Data {
    try Data(
      contentsOf: Self.localization.appendingPathComponent("\(language).lproj/Localizable.strings"))
  }

  private func table(_ language: String) throws -> String {
    let data = try tableData(language)
    return try XCTUnwrap(String(data: data, encoding: .utf8), "\(language) is not UTF-8")
  }

  func testLanguagesAreExactlyTheEightSupportedOnes() throws {
    let names = try FileManager.default.contentsOfDirectory(atPath: Self.localization.path)
      .filter { !$0.hasPrefix(".") }
    XCTAssertEqual(Set(names), Set(Self.languages.map { "\($0).lproj" }))
    for language in Self.languages {
      var isDirectory: ObjCBool = false
      let path = Self.localization.appendingPathComponent("\(language).lproj").path
      XCTAssertTrue(FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory))
      XCTAssertTrue(isDirectory.boolValue, language)
    }
  }

  func testEnglishKeysAreExactlyTheTextKeys() throws {
    let keys = parseTable(try table("en")).entries.map(\.key)
    XCTAssertEqual(Set(keys), Set(TextKey.allCases.map(\.rawValue)))
  }

  func testEveryLanguageHasEachEnglishKeyExactlyOnce() throws {
    let english = Set(parseTable(try table("en")).entries.map(\.key))
    for language in Self.languages {
      let keys = parseTable(try table(language)).entries.map(\.key)
      XCTAssertEqual(keys.count, Set(keys).count, "\(language) repeats a key")
      XCTAssertEqual(Set(keys), english, language)
    }
  }

  func testEveryTableFollowsTheSharedFormatAndPlaceholders() throws {
    for language in Self.languages {
      let data = try tableData(language)
      XCTAssertFalse(data.starts(with: [0xEF, 0xBB, 0xBF]), "\(language) has a BOM")
      XCTAssertEqual(tableProblems(base: Self.textKeyBase, raw: try table(language)), [], language)
    }
  }

  func testNoValueIsBlank() throws {
    for language in Self.languages {
      for entry in parseTable(try table(language)).entries {
        XCTAssertFalse(
          entry.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          "\(language): \(entry.key)")
      }
    }
  }

  func testSharedKeysArePendingAndKeepTheEnglishValue() throws {
    let english = Dictionary(
      uniqueKeysWithValues: parseTable(try table("en")).entries.map { ($0.key, $0.value) })
    for language in Self.languages {
      for entry in parseTable(try table(language)).entries {
        let key = try XCTUnwrap(TextKey(rawValue: entry.key), entry.key)
        XCTAssertEqual(entry.hasMarker, key.isShared, "\(language): \(entry.key)")
        if key.isShared {
          XCTAssertEqual(entry.value, english[entry.key], "\(language): \(entry.key)")
        }
      }
    }
  }

  // MARK: Validator properties

  private let sampleBase: [String: BaseKey] = [
    "About %@": BaseKey(isShared: true, value: "About %@"),
    "Hide Notch": BaseKey(isShared: false, value: "Hide Notch"),
    "Version %@ (%@)": BaseKey(isShared: false, value: "Version %@ (%@)"),
  ]

  private let sampleLines = [
    #"/* PENDING-MONOPODS */ "About %@" = "About %@";"#,
    #""Hide Notch" = "Nascondi notch";"#,
    #""Version %@ (%@)" = "Versione %1$@ (%2$@)";"#,
  ]

  private func sample(_ lines: [String]) -> String {
    lines.map { $0 + "\n" }.joined()
  }

  private func problems(_ lines: [String]) -> [TableProblem] {
    tableProblems(base: sampleBase, raw: sample(lines))
  }

  func testValidatorAcceptsAWellFormedTable() {
    XCTAssertEqual(problems(sampleLines), [])
    var sequential = sampleLines
    sequential[2] = #""Version %@ (%@)" = "Versione %@ (%@)";"#
    XCTAssertEqual(problems(sequential), [])
  }

  func testValidatorReportsEachStructuralDefect() {
    var lines = sampleLines

    XCTAssertTrue(
      problems(lines + [#""Hide Notch" = "Altro";"#]).contains(.duplicateKey("Hide Notch")))

    lines = sampleLines
    lines[1] = #""Hide Notch" = "Nascondi notch""#
    XCTAssertTrue(problems(lines).contains(.malformedLine(2)))

    XCTAssertTrue(problems(sampleLines + [#""Zebra" = "Zebra";"#]).contains(.extraKey("Zebra")))

    XCTAssertTrue(problems(Array(sampleLines.dropLast())).contains(.missingKey("Version %@ (%@)")))

    lines = sampleLines
    lines[1] = #""Hide Notch" = " ";"#
    XCTAssertTrue(problems(lines).contains(.emptyValue("Hide Notch")))
    lines[1] = #""Hide Notch" = "";"#
    XCTAssertTrue(problems(lines).contains(.emptyValue("Hide Notch")))

    let truncated = sample(Array(sampleLines.dropLast())) + #""Version %@ (%@)" = "Vers"#
    let truncatedProblems = tableProblems(base: sampleBase, raw: truncated)
    XCTAssertTrue(truncatedProblems.contains(.missingFinalNewline))
    XCTAssertTrue(truncatedProblems.contains(.malformedLine(3)))

    XCTAssertTrue(
      tableProblems(base: sampleBase, raw: "\u{FEFF}" + sample(sampleLines)).contains(
        .byteOrderMark))

    lines = sampleLines
    lines[1] = sampleLines[1] + " " + sampleLines[2]
    lines.remove(at: 2)
    XCTAssertTrue(problems(lines).contains(.malformedLine(2)))

    XCTAssertTrue(
      problems([sampleLines[1], sampleLines[0], sampleLines[2]]).contains(.unsorted(2)))

    XCTAssertTrue(problems(["/* Menu */"] + sampleLines).contains(.unexpectedComment(1)))
    lines = sampleLines
    lines[1] += " // note"
    XCTAssertTrue(problems(lines).contains(.unexpectedComment(2)))
    lines = sampleLines
    lines[1] = "/* other */ " + sampleLines[1]
    XCTAssertTrue(problems(lines).contains(.unexpectedComment(2)))

    lines = sampleLines
    lines[1] += "\r"
    XCTAssertTrue(problems(lines).contains(.malformedLine(2)))
  }

  func testValidatorReportsPlaceholderDefects() {
    let values: [(String, TableProblem)] = [
      ("Versione %@", .placeholderMismatch("Version %@ (%@)")),
      ("Versione %@ (%@) %@", .placeholderMismatch("Version %@ (%@)")),
      ("Versione %@ (%d)", .placeholderMismatch("Version %@ (%@)")),
      ("Versione %@ (%@) %%", .placeholderMismatch("Version %@ (%@)")),
      ("Versione %1$@ (%3$@)", .invalidPlaceholders("Version %@ (%@)")),
      ("Versione %1$@ (%1$@)", .invalidPlaceholders("Version %@ (%@)")),
      ("Versione %1$@ (%@)", .invalidPlaceholders("Version %@ (%@)")),
      ("Versione %s (%@)", .invalidPlaceholders("Version %@ (%@)")),
      ("Versione %@ (%@) %", .invalidPlaceholders("Version %@ (%@)")),
    ]
    for (value, expected) in values {
      var lines = sampleLines
      lines[2] = #""Version %@ (%@)" = ""# + value + #"";"#
      XCTAssertTrue(problems(lines).contains(expected), value)
    }
    XCTAssertEqual(placeholderSignature("%2$@ e %1$@")?.types, ["@", "@"])
    XCTAssertEqual(placeholderSignature("100%% %@")?.percents, 1)
  }

  func testValidatorEnforcesThePendingMarker() {
    var lines = sampleLines
    lines[0] = #""About %@" = "About %@";"#
    XCTAssertTrue(problems(lines).contains(.missingMarker("About %@")))

    lines = sampleLines
    lines[0] = #"/* PENDING-MONOPODS */ "About %@" = "Informazioni su %@";"#
    XCTAssertTrue(problems(lines).contains(.sharedValueChanged("About %@")))

    lines = sampleLines
    lines[1] = pendingMarker + " " + sampleLines[1]
    XCTAssertTrue(problems(lines).contains(.unexpectedMarker("Hide Notch")))
  }

  // MARK: Lookup

  func testLocalizerReadsTheInjectedTableAndFallsBackToEnglish() throws {
    let italianPath = Self.localization.appendingPathComponent("it.lproj").path
    let italian = Localizer(bundle: try XCTUnwrap(Bundle(path: italianPath)))
    let values = Dictionary(
      uniqueKeysWithValues: parseTable(try table("it")).entries.map { ($0.key, $0.value) })

    XCTAssertEqual(italian(.hideNotch), values[TextKey.hideNotch.rawValue])
    XCTAssertNotEqual(italian(.hideNotch), TextKey.hideNotch.rawValue)
    XCTAssertEqual(Localizer(bundle: .main)(.hideNotch), "Hide Notch")
    XCTAssertEqual(Localizer(bundle: .main)(.about, "TopNV"), "About TopNV")

    XCTAssertEqual(
      MenuStatus(hideNotch: true, roundCorners: false, localizer: italian).title,
      values[TextKey.notchHidden.rawValue])
    let custom = try XCTUnwrap(values[TextKey.customRadius.rawValue])
    XCTAssertEqual(
      CornerRadiusOption(value: 13, isCustom: true, localizer: italian).title,
      String(format: custom, "13"))
  }
}
