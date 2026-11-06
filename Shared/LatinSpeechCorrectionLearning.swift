import Foundation

/// Language-scoped corrections learned from repeated manual History edits.
/// This never retrains ASR weights or stores raw recordings/host text.
enum LatinSpeechCorrectionLearning {
  struct Rule: Codable, Hashable, Sendable {
    let language: String
    let heard: String
    let intended: String
  }

  static let storageKey = "canto.speech.verifiedLatinCorrections.v1"
  static let maximumRules = 40

  /// A multilingual recording is ambiguous; never teach a language from it.
  static func unambiguousLanguage(_ languages: [String]) -> String? {
    let codes = Set(languages.map { $0.lowercased().split(separator: "-").first.map(String.init) ?? "" })
    guard codes.count == 1, let code = codes.first, ["en", "de"].contains(code)
    else { return nil }
    return code
  }

  private static func isLatinWord(_ word: String) -> Bool {
    guard (2...32).contains(word.count) else { return false }
    return word.unicodeScalars.allSatisfy { scalar in
      (0x0041...0x005A).contains(scalar.value) ||
      (0x0061...0x007A).contains(scalar.value) ||
      (0x00C0...0x024F).contains(scalar.value) ||
      (0x1E00...0x1EFF).contains(scalar.value)
    }
  }

  /// Accept exactly one changed *complete* word. Paragraph rewrites,
  /// punctuation differences, capitalization-only and contractions do not
  /// provide reliable evidence for ASR substitutions.
  static func singleWordChange(heard: String, intended: String, language: String) -> Rule? {
    guard ["en", "de"].contains(language), heard != intended,
          (2...2000).contains(heard.count), (2...2000).contains(intended.count) else {
      return nil
    }
    let before = heard.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    let after = intended.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard before.count == after.count, (1...100).contains(before.count) else { return nil }
    var changed: (String, String)?
    for (old, new) in zip(before, after) where old != new {
      guard changed == nil, isLatinWord(old), isLatinWord(new),
            old.caseInsensitiveCompare(new) != .orderedSame else { return nil }
      changed = (old, new)
    }
    guard let changed else { return nil }
    return Rule(language: language, heard: changed.0, intended: changed.1)
  }

  static func recurringRules(in records: [HistoryRecord], minimumCount: Int = 3) -> [Rule] {
    var counts = [Rule: Int]()
    for record in records {
      guard let corrected = record.userCorrection,
            let language = unambiguousLanguage(record.recognitionLanguages),
            let rule = singleWordChange(
              heard: record.originalASR ?? record.transcription,
              intended: corrected, language: language
            ) else { continue }
      counts[rule, default: 0] += 1
    }
    let conflicting = Set(Dictionary(grouping: counts.keys, by: {
      $0.language + "|" + $0.heard.lowercased()
    }).filter { $0.value.count > 1 }.keys)
    return counts.filter { rule, count in
      count >= minimumCount &&
        !conflicting.contains(rule.language + "|" + rule.heard.lowercased())
    }.keys.sorted {
      $0.language == $1.language ? $0.heard < $1.heard : $0.language < $1.language
    }
  }

  static func read(defaults: UserDefaults?) -> [Rule] {
    guard let data = defaults?.data(forKey: storageKey),
          let decoded = try? JSONDecoder().decode([Rule].self, from: data)
    else { return [] }
    return Array(decoded.filter {
      ["en", "de"].contains($0.language) && isLatinWord($0.heard) &&
        isLatinWord($0.intended) && $0.heard != $0.intended
    }.prefix(maximumRules))
  }

  static func save(_ rules: [Rule], defaults: UserDefaults?) {
    guard let defaults else { return }
    let bounded = Array(rules.prefix(maximumRules))
    guard let data = try? JSONEncoder().encode(bounded) else { return }
    defaults.set(data, forKey: storageKey)
  }

  static func apply(
    _ recognized: String, languages: [String],
    defaults: UserDefaults?
  ) -> String {
    guard let language = unambiguousLanguage(languages),
          !recognized.isEmpty else { return recognized }
    var result = recognized
    for rule in read(defaults: defaults) where rule.language == language {
      // No substring matches inside longer words or German compounds.
      let pattern = #"(?<![\p{L}\p{N}])"#
        + NSRegularExpression.escapedPattern(for: rule.heard)
        + #"(?![\p{L}\p{N}])"#
      guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
      result = expression.stringByReplacingMatches(
        in: result,
        range: NSRange(result.startIndex..., in: result),
        withTemplate: NSRegularExpression.escapedTemplate(for: rule.intended)
      )
    }
    return result
  }
}
