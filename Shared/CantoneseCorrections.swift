import Foundation

/// Exact local phrase corrections that tolerate common ASR comma/space
/// variations. Applied without any LLM. The user's rules win over the
/// built-in homophone heuristic, so a saved rule is never preempted.
struct CantoneseCorrectionRule: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let heard: String
  let intended: String

  init(id: UUID = UUID(), heard: String, intended: String) {
    self.id = id
    self.heard = heard
    self.intended = intended
  }
}

struct CantoneseCorrectionResult: Equatable {
  let text: String
  let matchedRules: Int
}

enum CantoneseCorrections {
  static func apply(_ recognized: String, customRules: [CantoneseCorrectionRule]) -> String {
    applyDetailed(recognized, customRules: customRules).text
  }

  static func applyDetailed(
    _ recognized: String, customRules: [CantoneseCorrectionRule]
  ) -> CantoneseCorrectionResult {
    guard !recognized.isEmpty else {
      return CantoneseCorrectionResult(text: recognized, matchedRules: 0)
    }
    var text = recognized
    var count = 0

    // Match normal punctuation variants ("餵你" and "餵，你") without
    // replacing individual homophones throughout otherwise unrelated words.
    for rule in customRules.prefix(50) {
      let heard = rule.heard.trimmingCharacters(in: .whitespacesAndNewlines)
      let intended = rule.intended.trimmingCharacters(in: .whitespacesAndNewlines)
      let significant = heard.filter { char in
        char.unicodeScalars.allSatisfy { !self.optionalSeparators.contains($0) }
      }
      guard significant.count >= 2, heard.count <= 80,
            !intended.isEmpty, intended.count <= 80, heard != intended else { continue }

      let pattern = significant.map {
        NSRegularExpression.escapedPattern(for: String($0))
      }.joined(separator: #"[ \t,，、]{0,3}"#)
      guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
      let matches = expression.matches(
        in: text, range: NSRange(text.startIndex..., in: text)
      )
      for match in matches.reversed() {
        guard let range = Range(match.range, in: text) else { continue }
        text.replaceSubrange(range, with: intended)
        count += 1
      }
    }

    // Fall back to a narrow rule for greeting somebody. Do not modify
    // 餵食, 餵奶, or 餵你食飯. Custom rules already took precedence.
    text = self.greetingAtStart.stringByReplacingMatches(
      in: text,
      range: NSRange(text.startIndex..., in: text),
      withTemplate: "$1$2喂"
    )
    return CantoneseCorrectionResult(text: text, matchedRules: count)
  }

  private static let optionalSeparators = CharacterSet(charactersIn: " ,，、\t")

  private static let greetingAtStart: NSRegularExpression = try! NSRegularExpression(
    pattern: #"(^|[。！？!?\n])([ \t]*)餵(?=[，,！？!?]|你(?:做乜|點呀|喺邊|聽唔聽到)|阿)"#
  )
}
