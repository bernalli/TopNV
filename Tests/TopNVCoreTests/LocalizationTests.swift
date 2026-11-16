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
  case unexpectedMarker(String)
  case sharedValueChanged(String)
}

/// What a table must contain for one key: a shared key must have exactly `value`.
struct BaseKey {
  let isShared: Bool
  let value: String
}

/// The marker of the texts that waited for MonoPods; no table may carry it any more.
let pendingMarker = "/* PENDING-MONOPODS */"

struct ParsedEntry {
  let line: Int
  let key: String
  let value: String
  let hasMarker: Bool
}

private let entryPattern: NSRegularExpression = {
  let pattern = #"^(/\* PENDING-MONOPODS \*/ )?"((?:[^"\\]|\\.)*)" = "((?:[^"\\]|\\.)*)";\z"#
  do {
    return try NSRegularExpression(pattern: pattern)
  } catch {
    preconditionFailure("invalid entry pattern: \(error)")
  }
}()

/// The only escapes of the shared format. Checked before Foundation decodes the text, because
/// Foundation's handling of other escapes differs between macOS versions.
private let allowedEscape: NSRegularExpression = {
  do {
    return try NSRegularExpression(pattern: #"\A(?:[^\\]|\\[\\"ntr]|\\U[0-9A-Fa-f]{4})*\z"#)
  } catch {
    preconditionFailure("invalid escape pattern: \(error)")
  }
}()

private func unescape(_ text: String) -> String? {
  let whole = NSRange(text.startIndex..., in: text)
  guard allowedEscape.firstMatch(in: text, range: whole) != nil else { return nil }
  let entry = "\"value\" = \"\(text)\";\n"
  guard
    let plist = try? PropertyListSerialization.propertyList(
      from: Data(entry.utf8), options: [], format: nil),
    let dictionary = plist as? [String: String]
  else { return nil }
  return dictionary["value"]
}

/// Parses the shared format: UTF-8 without BOM, one `"key" = "value";` per line, lines sorted
/// by UTF-8 bytes (ignoring the marker), no comments. The old pending marker is still parsed,
/// so that a leftover one is reported as `unexpectedMarker` rather than as a bare comment.
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
      let valueRange = Range(match.range(at: 3), in: line),
      let key = unescape(String(line[keyRange])),
      let value = unescape(String(line[valueRange]))
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
        line: number, key: key,
        value: value,
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
    if entry.hasMarker { problems.append(.unexpectedMarker(entry.key)) }
    if expected.isShared, entry.value != expected.value {
      problems.append(.sharedValueChanged(entry.key))
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

  /// Shared keys must carry the MonoPods text of the language; own keys only need to exist.
  private static func textKeyBase(_ language: String) -> [String: BaseKey] {
    Dictionary(
      uniqueKeysWithValues: TextKey.allCases.filter(\.isInTables).map {
        let shared = $0.isShared ? monoPodsSharedTexts[language]?[$0.rawValue] : nil
        return ($0.rawValue, BaseKey(isShared: $0.isShared, value: shared ?? $0.rawValue))
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
    XCTAssertEqual(Set(keys), Set(TextKey.allCases.filter(\.isInTables).map(\.rawValue)))
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
      XCTAssertEqual(
        tableProblems(base: Self.textKeyBase(language), raw: try table(language)), [], language)
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

  func testNoTableCarriesThePendingMarker() throws {
    for language in Self.languages {
      XCTAssertFalse(try table(language).contains("PENDING-MONOPODS"), language)
      XCTAssertFalse(try driverTable(language).text.contains("PENDING-MONOPODS"), language)
      for entry in parseTable(try table(language)).entries {
        XCTAssertFalse(entry.hasMarker, "\(language): \(entry.key)")
      }
    }
  }

  /// The shared keys are exactly the keys of the MonoPods table, with its text in every language.
  func testSharedKeysCarryTheMonoPodsTexts() throws {
    let shared = Set(TextKey.allCases.filter(\.isShared).map(\.rawValue))
    XCTAssertEqual(Set(monoPodsSharedTexts.keys), Set(Self.languages))
    for language in Self.languages {
      let expected = try XCTUnwrap(monoPodsSharedTexts[language], language)
      XCTAssertEqual(Set(expected.keys), shared, language)
      let values = Dictionary(
        uniqueKeysWithValues: parseTable(try table(language)).entries.map { ($0.key, $0.value) })
      for key in shared.sorted() {
        XCTAssertEqual(values[key], expected[key], "\(language): \(key)")
      }
    }
  }

  /// The translation revisions of this release, as a closed list.
  func testMenuTranslationRevisions() throws {
    let expected: [String: [String: String]] = [
      "de": ["Launch at Login": "Bei der Anmeldung öffnen"],
      "pt-BR": [
        "Launch at Login": "Abrir ao Iniciar Sessão",
        "Quit %@": "Encerrar %@",
        "Hide Menu Bar Icon": "Ocultar Ícone da Barra de Menus",
        "Report an Issue…": "Relatar um Problema…",
        "Hide Notch": "Ocultar Entalhe",
        "Round Corners": "Arredondar Cantos",
        "Allow %@ in System Settings > General > Login Items.":
          "Permita o %@ em Ajustes do Sistema > Geral > Itens de Início de Sessão.",
      ],
      "es": [
        "Allow %@ in System Settings > General > Login Items.":
          "Permite %@ en Ajustes del Sistema > General > Ítems de inicio."
      ],
      "ja": [
        "Allow %@ in System Settings > General > Login Items.":
          "システム設定 > 一般 > ログイン項目で%@を許可してください。"
      ],
    ]
    for (language, values) in expected {
      let entries = Dictionary(
        uniqueKeysWithValues: parseTable(try table(language)).entries.map { ($0.key, $0.value) })
      for (key, value) in values {
        XCTAssertEqual(entries[key], value, "\(language): \(key)")
      }
    }
  }

  /// The key set of this release, as a closed list per scope.
  func testTheKeySetIsTheOneOfTheMenu() {
    func keys(_ scope: TextKey.Scope) -> Set<String> {
      Set(TextKey.allCases.filter { $0.scope == scope }.map(\.rawValue))
    }
    XCTAssertEqual(
      keys(.topNV),
      [
        "Hide Notch", "Black menu bar on light wallpapers", "Round Corners", "Round Corners on All Displays",
        "Launch at Login (Requires Approval)",
        "Allow %@ in System Settings > General > Login Items.",
      ])
    XCTAssertEqual(
      keys(.shared),
      [
        "Options", "Launch at Login", "Hide Menu Bar Icon", "Open %@ again to bring it back.",
        "Check for Updates Automatically", "Check for Updates…", "About %@", "Report an Issue…",
        "Quit %@", "Check for Updates Automatically?",
        "%@ can check for new versions once a day. You can change this at any time in Options.",
        "Check Automatically", "Don't Check",
      ])
    XCTAssertEqual(keys(.englishOnly), ["Version %@", "Version Unavailable"])
  }

  /// The About window is English: its texts are in no table.
  func testEnglishOnlyKeysAreInNoTable() throws {
    let englishOnly = TextKey.allCases.filter { !$0.isInTables }.map(\.rawValue)
    XCTAssertFalse(englishOnly.isEmpty)
    for language in Self.languages {
      let keys = Set(parseTable(try table(language)).entries.map(\.key))
      for key in englishOnly {
        XCTAssertFalse(keys.contains(key), "\(language): \(key)")
      }
    }
  }

  // MARK: Keys used by the code

  private enum KeyScanError: Error { case unsupportedCall(String) }

  /// The TextKey case names that a source passes as a literal to a localizer. A call with any
  /// other first argument throws, because this scan cannot follow it. Text after `//` is ignored.
  static func localizedCaseNames(in source: String) throws -> Set<String> {
    let code = source.components(separatedBy: "\n").map { line -> String in
      guard let range = line.range(of: "//") else { return line }
      return String(line[..<range.lowerBound])
    }.joined(separator: "\n")
    let call = try NSRegularExpression(
      pattern: #"(?<![\w.])(?:localizer|Localizer\.main|Localizer\.english)\s*\("#)
    let literal = try NSRegularExpression(pattern: #"\A\s*\.([a-z]\w*)\s*[,)]"#)
    let text = code as NSString
    var names: Set<String> = []
    for match in call.matches(in: code, range: NSRange(location: 0, length: text.length)) {
      let rest = text.substring(from: match.range.location + match.range.length)
      let restText = rest as NSString
      guard
        let found = literal.firstMatch(
          in: rest, range: NSRange(location: 0, length: restText.length))
      else { throw KeyScanError.unsupportedCall(String(rest.prefix(40))) }
      names.insert(restText.substring(with: found.range(at: 1)))
    }
    return names
  }

  func testTheKeyScanReadsLiteralKeysAndRejectsOtherArguments() throws {
    XCTAssertEqual(
      try Self.localizedCaseNames(
        in: "localizer(.hideNotch)\nlocalizer( .about, name)\nLocalizer.english(.version, v)\n"
          + "Localizer.main(.options)\nlocalizer(\n  .quit, name)"),
      ["hideNotch", "about", "version", "options", "quit"])
    XCTAssertEqual(
      try Self.localizedCaseNames(
        in: "// localizer(.details)\nlet localizer: Localizer = .main\nrun(localizer: localizer)\n"
          + "myLocalizer(.x)\nLocalizer(bundle: .main)"),
      [])
    for fragment in [
      "localizer(scope)", "localizer(flag ? .a : .b)", "Localizer.main(key)", "localizer(\n key)",
      "localizer()",
    ] {
      XCTAssertThrowsError(try Self.localizedCaseNames(in: fragment), fragment)
    }
  }

  /// Every key is shown by some code, and the code looks up no key that does not exist.
  func testEveryKeyIsUsedAndEveryLookupHasAKey() throws {
    var used: Set<String> = []
    for folder in ["Sources/TopNV", "Sources/TopNVCore"] {
      let url = Self.repository.appendingPathComponent(folder)
      for name in try FileManager.default.contentsOfDirectory(atPath: url.path)
      where name.hasSuffix(".swift") {
        let source = try String(contentsOf: url.appendingPathComponent(name), encoding: .utf8)
        used.formUnion(try Self.localizedCaseNames(in: source))
      }
    }
    let cases = Set(TextKey.allCases.map { "\($0)" })
    XCTAssertGreaterThan(used.count, 10, "the scan must read the real sources")
    XCTAssertEqual(cases.subtracting(used), [], "keys that no code shows")
    XCTAssertEqual(used.subtracting(cases), [], "lookups of keys that do not exist")
  }

  // MARK: Update window table

  private static let driverTable = "AppleStyleUpdateDriver.strings"

  private func driverTable(_ language: String) throws -> (data: Data, text: String) {
    let data = try Data(
      contentsOf: Self.localization.appendingPathComponent("\(language).lproj/\(Self.driverTable)"))
    return (data, try XCTUnwrap(String(data: data, encoding: .utf8), "\(language) is not UTF-8"))
  }

  /// The copied update window looks its texts up in its own table, with the English keys of `en`.
  func testEveryLanguageHasTheUpdateWindowTableWithTheEnglishKeys() throws {
    let english = parseTable(try driverTable("en").text)
    XCTAssertEqual(english.problems, [])
    XCTAssertFalse(english.entries.isEmpty)
    let base = Dictionary(
      uniqueKeysWithValues: english.entries.map {
        ($0.key, BaseKey(isShared: false, value: $0.value))
      })
    for language in Self.languages {
      let table = try driverTable(language)
      XCTAssertFalse(table.data.starts(with: [0xEF, 0xBB, 0xBF]), "\(language) has a BOM")
      XCTAssertEqual(tableProblems(base: base, raw: table.text), [], language)
    }
  }

  private enum DriverKeyError: Error {
    case unsupportedLookup, invalidEscape
  }

  /// Restricted source gate: unknown lookup syntax must fail.
  private func updateDriverKeys(in source: String) throws -> Set<String> {
    let declaration = try NSRegularExpression(
      pattern: #"\bfunc\s+localized(?=\s*\()"#)
    let code = declaration.stringByReplacingMatches(
      in: source, range: NSRange(source.startIndex..., in: source),
      withTemplate: "")
    let call = try NSRegularExpression(
      pattern: #"\blocalized\s*\(\s*"((?:[^"\\\r\n]|\\.)*)"\s*\)"#)
    let range = NSRange(code.startIndex..., in: code)
    let matches = call.matches(in: code, range: range)
    let remaining = call.stringByReplacingMatches(
      in: code, range: range, withTemplate: "")
    let reference = try NSRegularExpression(pattern: #"\blocalized\b"#)
    guard !matches.isEmpty,
      reference.firstMatch(
        in: remaining,
        range: NSRange(remaining.startIndex..., in: remaining)) == nil
    else { throw DriverKeyError.unsupportedLookup }

    let allowed = try NSRegularExpression(
      pattern: #"\A(?:[^\\]|\\(?:[0\\nrt"]|u\{[0-9A-Fa-f]{1,8}\}))*\z"#)
    let escape = try NSRegularExpression(
      pattern: #"\\(?:u\{([0-9A-Fa-f]{1,8})\}|([0\\nrt"]))"#)
    let simple = [
      "0": "\0", "\\": "\\", "n": "\n",
      "r": "\r", "t": "\t", "\"": "\"",
    ]
    var keys: Set<String> = []
    for match in matches {
      let literal = (code as NSString).substring(with: match.range(at: 1))
      let whole = NSRange(literal.startIndex..., in: literal)
      guard allowed.firstMatch(in: literal, range: whole) != nil
      else { throw DriverKeyError.invalidEscape }
      let key = NSMutableString(string: literal)
      for found in escape.matches(in: literal, range: whole).reversed() {
        let replacement: String
        if found.range(at: 1).location != NSNotFound {
          let hex = (literal as NSString).substring(with: found.range(at: 1))
          guard let value = UInt32(hex, radix: 16),
            let scalar = Unicode.Scalar(value)
          else { throw DriverKeyError.invalidEscape }
          replacement = String(scalar)
        } else {
          let token = (literal as NSString).substring(with: found.range(at: 2))
          guard let value = simple[token]
          else { throw DriverKeyError.invalidEscape }
          replacement = value
        }
        key.replaceCharacters(in: found.range, with: replacement)
      }
      keys.insert(key as String)
    }
    return keys
  }

  func testDriverKeyExtractionPreservesWhitespaceEscapesAndOrdering() throws {
    XCTAssertEqual(
      try updateDriverKeys(
        in: #"localized( "Later" )"# + "\n" + #"localized("#
          + "\n" + #""New\u{2026}""# + "\n)"),
      Set(["Later", "New…"]))
    XCTAssertEqual(
      try updateDriverKeys(in: #"localized("a\"b\\c\n")"#),
      Set(["a\"b\\c\n"]))
    XCTAssertEqual(
      try updateDriverKeys(in: #"localized("\\u{0041}")"#),
      Set([#"\u{0041}"#]))
    XCTAssertEqual(
      try updateDriverKeys(
        in: #"localized("B"); localized("A"); localized("B")"#),
      Set(["A", "B"]))
  }

  func testDriverKeyExtractionRejectsUnsupportedOrTruncatedLookups() {
    for fragment in [
      #"localized(value)"#, #"localized("Later", extra)"#,
      #"localized()"#, #"localized("unterminated"#, #"localized("Later""#,
      #"localized("bad\q")"#, #"localized("bad\u{}")"#,
      #"localized("bad\u{D800}")"#, #"localized("bad\u{110000}")"#,
      #"localized("bad\u{FFFFFFFFF}")"#, #"localized("bad\(value)")"#,
    ] {
      XCTAssertThrowsError(
        try updateDriverKeys(
          in: #"localized("Later")"# + "\n" + fragment),
        fragment)
    }
    XCTAssertThrowsError(try updateDriverKeys(in: ""))
  }

  /// Every admitted literal lookup has an English entry, and nothing more.
  func testTheUpdateWindowTableHasExactlyTheKeysTheDriverLooksUp() throws {
    let source = try String(
      contentsOf: Self.repository.appendingPathComponent(
        "Sources/TopNV/AppleStyleUpdateDriver.swift"),
      encoding: .utf8)
    let keys = try updateDriverKeys(in: source)
    XCTAssertEqual(
      Set(parseTable(try driverTable("en").text).entries.map(\.key)), keys)
  }

  /// The update window names the app with one gender, and Later uses the term of the update
  /// notification of macOS.
  func testUpdateWindowTranslationRevisions() throws {
    let expected: [String: [String: String]] = [
      "it": [
        "%@ is ready to install.": "%@ è pronto per l’installazione.",
        "%@ is up to date.": "%@ è aggiornato.",
      ],
      "es": [
        "%@ is ready to install.": "%@ está listo para instalarse.",
        "%@ is up to date.": "%@ está actualizado.",
      ],
      "fr": ["%@ is ready to install.": "%@ est prêt à être installé."],
      "zh-Hans": ["Later": "稍后"],
    ]
    for (language, values) in expected {
      let entries = Dictionary(
        uniqueKeysWithValues: parseTable(try driverTable(language).text).entries.map {
          ($0.key, $0.value)
        })
      for (key, value) in values {
        XCTAssertEqual(entries[key], value, "\(language): \(key)")
      }
    }
  }

  // MARK: Validator properties

  private let sampleBase: [String: BaseKey] = [
    "About %@": BaseKey(isShared: true, value: "Informazioni su %@"),
    "Hide Notch": BaseKey(isShared: false, value: "Hide Notch"),
    "Version %@ (%@)": BaseKey(isShared: false, value: "Version %@ (%@)"),
  ]

  private let sampleLines = [
    #""About %@" = "Informazioni su %@";"#,
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

  func testValidatorUsesFoundationEscapeRules() {
    var lines = sampleLines
    for blank in [#"\t"#, #"\r"#, #"\U0020"#] {
      lines[1] = #""Hide Notch" = ""# + blank + #"";"#
      XCTAssertTrue(problems(lines).contains(.emptyValue("Hide Notch")), blank)
    }
    // The shared format allows only \\ \" \n \t \r and \U followed by four hex digits, so the
    // verdict does not depend on how a given macOS version's Foundation treats other escapes.
    for invalid in [
      #""Hide Notch" = "\UZZZZ";"#, #""Hide Notch" = "\U12";"#,
      #""Hide Notch" = "\q";"#, #""Hide Notch" = "\012";"#, #""Hide Notch" = 7;"#,
      sampleLines[1] + " extra",
    ] {
      lines = sampleLines
      lines[1] = invalid
      XCTAssertTrue(problems(lines).contains(.malformedLine(2)), invalid)
    }
    let base = ["%@ pt": BaseKey(isShared: false, value: "%@ pt")]
    XCTAssertTrue(
      tableProblems(base: base, raw: #""%@ pt" = "\U0025d %@";"# + "\n")
        .contains(.placeholderMismatch("%@ pt")))
    XCTAssertEqual(
      tableProblems(base: base, raw: #""%@ pt" = "\U0025@ pt";"# + "\n"), [])
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

  func testValidatorRejectsThePendingMarkerAndOtherSharedTexts() {
    var lines = sampleLines
    lines[0] = pendingMarker + " " + sampleLines[0]
    XCTAssertTrue(problems(lines).contains(.unexpectedMarker("About %@")))

    lines = sampleLines
    lines[0] = #""About %@" = "About %@";"#
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

    let rows = MenuLayout.rows(
      for: MenuState(
        hideNotch: true, roundCorners: true, cornersOnAllDisplays: false, launchAtLogin: false,
        loginNeedsApproval: false, loginError: nil, updates: .hidden),
      localizer: italian)
    XCTAssertEqual(rows.first { $0.id == "hideNotch" }?.title, values[TextKey.hideNotch.rawValue])
  }
}
