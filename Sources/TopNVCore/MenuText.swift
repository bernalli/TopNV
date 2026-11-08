public enum MenuText {
  /// Native menu rows do not wrap, so notices need separate rows to remain readable.
  public static func lines(_ text: String, width: Int = 44) -> [String] {
    let limit = max(1, width)
    var lines: [String] = []
    var current = ""
    for word in text.split(whereSeparator: \.isWhitespace) {
      var word = word
      while word.count > limit {
        if !current.isEmpty {
          lines.append(current)
          current = ""
        }
        lines.append(String(word.prefix(limit)))
        word = word.dropFirst(limit)
      }
      if word.isEmpty { continue }
      if current.isEmpty {
        current = String(word)
      } else if current.count + 1 + word.count <= limit {
        current += " " + word
      } else {
        lines.append(current)
        current = String(word)
      }
    }
    if !current.isEmpty { lines.append(current) }
    return lines
  }
}
