import CoreGraphics
import Foundation
import ImageIO

public enum BarCheck {
  public static let blackLimit = 0.05
  public static let rowsBelow = 4

  public struct Summary {
    public let time: Date
    public let display: UInt32
    public let scene: String
    public let band: String
    public let width, height: Int
    public let scale: Double
    public let blackBottom: Int
  }

  public struct Log {
    public fileprivate(set) var summaries: [Summary] = []
    public fileprivate(set) var mismatches: [UInt32: [Date]] = [:]
    public fileprivate(set) var ignoredLines = 0
  }

  private static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = format
    formatter.isLenient = false
    return formatter
  }

  public static func parseLog(_ text: String, timeZone: TimeZone) -> Log {
    let clock = formatter("yyyy-MM-dd HH:mm:ss.SSS", timeZone: timeZone)
    let envelope = #/([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}) .*\[TopNV:BarSurface\] (.+)/#
    let prefix = #/display=([0-9]+) scene=(desktop|revealed|overview|fullScreen|sliding|unknown|absent) part=(.+)/#
    var log = Log()
    text.enumerateLines { line, _ in
      guard let header = line.wholeMatch(of: envelope),
            let fields = header.2.wholeMatch(of: prefix), let display = UInt32(fields.1),
            let time = clock.date(from: String(header.1)), clock.string(from: time) == header.1 else {
        log.ignoredLines += 1
        return
      }
      if let summary = parseSummary(fields.3, time: time, display: display, scene: String(fields.2)) {
        log.summaries.append(summary)
      } else if let mismatch = parsePart(fields.3) {
        if mismatch { log.mismatches[display, default: []].append(time) }
      } else {
        log.ignoredLines += 1
      }
    }
    return log
  }

  private static func parseSummary(_ fields: Substring, time: Date, display: UInt32, scene: String) -> Summary? {
    let format = #/summary band=(on|off) screenPx=([0-9]+)x([0-9]+) scale=(\S+) blackBottom=(0|[1-9][0-9]*)/#
    guard let match = fields.wholeMatch(of: format),
          let width = Int(match.2), width > 0, let height = Int(match.3), height > 0,
          let scale = decimal(match.4), scale > 0, let bottom = Int(match.5) else { return nil }
    return Summary(time: time, display: display, scene: scene, band: String(match.1),
                   width: width, height: height, scale: scale, blackBottom: bottom)
  }

  // The registry emits ordinary decimal notation with at most three fractional digits and no trailing zeros.
  private static func decimal(_ field: Substring) -> Double? {
    guard field.wholeMatch(of: #/-?(?:0|[1-9][0-9]*)(?:\.[0-9]{0,2}[1-9])?/#) != nil,
          let value = Double(field), value.isFinite else { return nil }
    return value
  }

  private static func integer(_ field: Substring) -> Bool {
    field.wholeMatch(of: #/-?(?:0|[1-9][0-9]*)/#) != nil && Int(field) != nil
  }

  private static func rectangle(_ field: Substring) -> Bool {
    let coordinates = field.split(separator: ",", omittingEmptySubsequences: false)
    return coordinates.count == 4 && coordinates.allSatisfy(integer)
  }

  private static func validListing(_ listing: Substring) -> Bool {
    switch listing {
    case "none", "offspace", "ambiguous", "unavailable", "n/a": return true
    default:
      let fields = listing.split(separator: "/", omittingEmptySubsequences: false)
      return fields.count == 2 && rectangle(fields[0]) && decimal(fields[1]) != nil
    }
  }

  private static func parsePart(_ fields: Substring) -> Bool? {
    let part = #/(band|key|plate|edge|corner\.(?:topLeft|topRight|bottomLeft|bottomRight)) (.+)/#
    let format = #/px=(\S+) alpha=(\S+) level=(\S+) window=(\S+) mask=(\S+)(?: listed=(\S+)(?: MISMATCH)?)?/#
    guard let entry = fields.wholeMatch(of: part), let match = entry.2.wholeMatch(of: format),
          match.1 == "none" || rectangle(match.1), decimal(match.2) != nil, integer(match.3),
          match.4 == "none" || integer(match.4),
          match.5 == "none" || match.5 == "empty" || rectangle(match.5) else { return nil }
    if let listing = match.6, !validListing(listing) { return nil }
    return fields.hasSuffix(" MISMATCH")
  }
}

extension BarCheck {
  public static func rowMedians(_ image: CGImage, rows: Range<Int>) -> [Double] {
    let selected = rows.clamped(to: 0..<image.height)
    guard !selected.isEmpty else { return [] }
    let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
    let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    guard let space, let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: space, bitmapInfo: info),
          let data = context.data else { return [] }
    context.setBlendMode(.copy)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    var luminances = Array(repeating: 0.0, count: image.width)
    return selected.map { row in
      let scanline = bytes.advanced(by: row * context.bytesPerRow)
      for column in luminances.indices {
        let offset = column * 4
        let red = Double(scanline[offset]), green = Double(scanline[offset + 1]), blue = Double(scanline[offset + 2])
        luminances[column] = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
      }
      luminances.sort()
      return luminances[(image.width - 1) / 2]
    }
  }

  private static func luminance(_ value: Double) -> String {
    String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
  }

  public static func verdict(medians: [Double], summary: Summary, mismatches: Int) -> (line: String, exitCode: Int32) {
    let bottom = summary.blackBottom
    let identity = "display \(summary.display), scene \(summary.scene)"
    guard bottom > 0 else { return ("FAIL black bar was inactive (\(identity), band \(summary.band))", 1) }
    guard bottom < summary.height else {
      return ("FAIL blackBottom \(bottom) outside capture of height \(summary.height)", 1)
    }
    guard medians.indices.contains(bottom) else { return ("FAIL unable to measure capture rows", 1) }

    let measured = medians[..<bottom].prefix(while: { $0 <= blackLimit }).count
    let details = "\(identity), MISMATCH \(mismatches)"
    if measured < bottom {
      let misplaced = (measured..<bottom).filter { medians[$0] > blackLimit }
      let samples = misplaced.prefix(12).map { "\($0)=\(luminance(medians[$0]))" }.joined(separator: " ")
      let remainder = misplaced.count > 12 ? " … (+\(misplaced.count - 12))" : ""
      let span = measured == 0 ? "none" : "0-\(measured - 1)"
      return ("FAIL expected black 0-\(bottom - 1), measured black \(span); misplaced \(samples)\(remainder); "
                + "row \(bottom)=\(luminance(medians[bottom])); \(details)", 1)
    }
    if medians[bottom] <= blackLimit {
      return ("DUBIOUS rows 0-\(bottom) black; no light background below the bar; "
                + "retake the screenshot without windows below the bar; \(details)", 3)
    }
    return ("OK rows 0-\(bottom - 1) black; row \(bottom) background (\(luminance(medians[bottom]))); \(details)", 0)
  }
}

extension BarCheck {
  private static func paths(_ arguments: [String]) -> (log: URL, capture: URL)? {
    guard arguments.count == 4 else { return nil }
    var paths: [String: URL] = [:]
    for index in [0, 2] {
      let option = arguments[index], path = arguments[index + 1]
      guard ["--log", "--capture"].contains(option), paths[option] == nil,
            !path.isEmpty, !path.hasPrefix("--") else { return nil }
      paths[option] = URL(fileURLWithPath: path)
    }
    guard let log = paths["--log"], let capture = paths["--capture"] else { return nil }
    return (log, capture)
  }

  // swiftlint:disable:next large_tuple
  public static func run(arguments: [String], timeZone: TimeZone) -> (line: String, exitCode: Int32, usage: Bool) {
    guard let files = paths(arguments) else {
      return ("bar-check: usage: bar-check --log <file> --capture <png>", 2, true)
    }
    guard let source = CGImageSourceCreateWithURL(files.capture as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let time = try? files.capture.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    else { return ("FAIL unable to read capture (\(files.capture.lastPathComponent))", 1, false) }
    guard let text = try? String(contentsOf: files.log, encoding: .utf8) else {
      return ("FAIL unable to read registry log (\(files.log.lastPathComponent))", 1, false)
    }
    let log = parseLog(text, timeZone: timeZone)
    guard let summary = log.summaries.last(where: {
      $0.time <= time && $0.width == image.width && $0.height == image.height
    }) else {
      let clock = formatter("HH:mm:ss", timeZone: timeZone).string(from: time)
      return ("FAIL no registry line for a \(image.width)x\(image.height) capture before \(clock)", 1, false)
    }
    let bottom = summary.blackBottom
    let mismatches = log.mismatches[summary.display, default: []].filter { $0 <= time }.count
    var medians: [Double] = []
    if bottom > 0, bottom < image.height {
      let end = bottom + min(rowsBelow, image.height - bottom)
      medians = rowMedians(image, rows: 0..<end)
    }
    let result = verdict(medians: medians, summary: summary, mismatches: mismatches)
    return (result.line, result.exitCode, false)
  }
}
