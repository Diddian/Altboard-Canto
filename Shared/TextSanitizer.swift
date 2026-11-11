
import Foundation

enum TextSanitizer {

  static func sanitize(_ text: String) -> String {
    var result = text

    // A Qwen language header is model metadata, not dictated speech.
    // Detect the ASR marker rather than limiting cleanup to preferred languages.
    result = self.qwenLanguageHeaderPattern.stringByReplacingMatches(
      in: result,
      range: NSRange(result.startIndex..., in: result)
    )

    result = self.qwenControlHeaderPattern.stringByReplacingMatches(
      in: result,
      range: NSRange(result.startIndex..., in: result)
    )

    result = self.whisperTokenPattern.stringByReplacingMatches(
      in: result,
      range: NSRange(result.startIndex..., in: result),
    )

    result = result.replacingOccurrences(of: "<unk>", with: "")

    result = self.bracketAnnotationPattern.stringByReplacingMatches(
      in: result,
      range: NSRange(result.startIndex..., in: result),
    )

    result = String(result.filter { !self.musicalNoteSymbols.contains($0) })

    result = result.replacingOccurrences(of: "\u{FFFD}", with: "")

    result = self.collapseWhitespace(result)

    return result
  }

  // Only remove a leading language label if a recognizer control marker follows.
  // Accept any detected language, including languages outside the preference list.
  private static let qwenLanguageHeaderPattern: NSRegularExpression =
    try! NSRegularExpression(
      pattern: #"^\s*(?:language[ \t]*[:\x{FF1A}]?[ \t]+|<\|language\|>[ \t]*)[^\r\n<>]{1,64}?(?:(?:->|=>|\x{2192}|\x{27A1}|\x{279C})[ \t]*)?(?:<asr_text>|<\|asr_text\|>|<text_sentinel>|<\|text_sentinel\|>|ASR[ \t_]+text)[ \t]*(?:(?:->|=>|\x{2192}|\x{27A1}|\x{279C}|[:\x{FF1A}])[ \t]*)?"#,
      options: [.caseInsensitive]
    )

  private static let qwenControlHeaderPattern: NSRegularExpression =
    try! NSRegularExpression(
      pattern: #"^\s*(?:<asr_text>|<\|asr_text\|>|<text_sentinel>|<\|text_sentinel\|>)[ \t]*(?:(?:->|=>|\x{2192}|\x{27A1}|\x{279C})[ \t]*)?"#,
      options: [.caseInsensitive]
    )

  private static let whisperTokenPattern: NSRegularExpression =
    try! NSRegularExpression(pattern: #"<\|[^|]+\|>"#)

  private static let bracketAnnotationPattern: NSRegularExpression =
    try! NSRegularExpression(pattern: #"\[[\w\s]+\]|\([\w\s]+\)"#)

  private static let musicalNoteSymbols: Set<Character> = [
    "\u{2669}",
    "\u{266A}",
    "\u{266B}",
    "\u{266C}",
    "\u{266D}",
    "\u{266E}",
    "\u{266F}",
  ]

  private static func collapseWhitespace(_ text: String) -> String {
    var result = text
    while result.contains("  ") {
      result = result.replacingOccurrences(of: "  ", with: " ")
    }
    return result.trimmingCharacters(in: .whitespaces)
  }
}

extension NSRegularExpression {
  fileprivate func stringByReplacingMatches(in string: String, range: NSRange) -> String {
    self.stringByReplacingMatches(in: string, range: range, withTemplate: "")
  }
}
