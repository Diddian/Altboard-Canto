import Foundation

/// Pure rules shared by the app, keyboard and headless smoke tests.
/// Language preferences are taken from "Languages I Speak"; there is no
/// second English/German/Cantonese mode switch.
enum LatinWordSuggestionPolicy {
  struct CheckerLocale: Equatable {
    let preference: String
    let identifier: String
  }

  /// Prefer the selected languages in the user's own order. Han scripts
  /// are handled by the separate Cantonese IME, not the Latin spell checker.
  static func preferredCodes(_ preferred: [String]) -> [String] {
    var seen = Set<String>()
    return preferred.compactMap { value in
      let code = value.lowercased()
        .replacingOccurrences(of: "-", with: "_")
        .split(separator: "_").first.map(String.init) ?? ""
      guard code.count == 2, code != "zh", seen.insert(code).inserted else { return nil }
      return code
    }
  }

  static func checkerLocales(preferred: [String], available: [String]) -> [CheckerLocale] {
    let codes = preferredCodes(preferred)
    var resolved = [CheckerLocale]()
    for code in codes {
      if let identifier = available.first(where: { candidate in
        let lower = candidate.lowercased()
        return lower == code || lower.hasPrefix(code + "_") || lower.hasPrefix(code + "-")
      }) {
        resolved.append(CheckerLocale(preference: code, identifier: identifier))
      }
    }
    return resolved
  }

  /// Take only the word immediately before the cursor. Never inspect or
  /// save the rest of the host's text. Works for German umlauts and ß.
  static func trailingWord(in context: String?) -> String? {
    guard let context, !context.isEmpty else { return nil }
    let characters = context.reversed().prefix { character in
      isLatinLetter(character) || character == "'" || character == "’"
    }
    let word = String(characters.reversed())
    guard (2...32).contains(word.count),
          let first = word.first, let last = word.last,
          isLatinLetter(first), isLatinLetter(last) else { return nil }
    return word
  }

  /// Replacements never run unless the original word still exists directly
  /// to the left of the cursor. This prevents corrupting host text after a
  /// cursor move, external edit, or extension callback delay.
  static func canReplace(_ typed: String, in context: String?) -> Bool {
    guard let context, trailingWord(in: context) == typed else { return false }
    return context.hasSuffix(typed)
  }

  static func matchCapitalization(_ suggestion: String, typed: String) -> String {
    guard let first = typed.first, first.isUppercase else { return suggestion }
    if typed.count > 1 && typed == typed.uppercased() {
      return suggestion.uppercased()
    }
    return suggestion.prefix(1).uppercased() + suggestion.dropFirst()
  }

  /// A small offline safety net when UITextChecker is unavailable or does not
  /// offer a candidate. Keep prefix matches first; only suggest one-edit
  /// corrections as explicit choices, never automatic replacements.
  static func fallbackCandidates(
    for typed: String, dictionary: [String], limit: Int = 12
  ) -> [String] {
    guard (2...32).contains(typed.count), limit > 0 else { return [] }
    let normalized = typed.lowercased()
    var results: [String] = []
    var seen = Set<String>()
    func append(_ word: String) {
      let lower = word.lowercased()
      guard word.count <= 36, lower != normalized,
            seen.insert(lower).inserted else { return }
      results.append(word)
    }
    for word in dictionary where results.count < limit {
      if word.lowercased().hasPrefix(normalized) { append(word) }
    }
    // A short prefix has too many one-edit neighbors to be meaningful.
    if typed.count >= 4 && results.count < limit {
      for word in dictionary where results.count < limit {
        if oneEditApart(normalized, word.lowercased()) { append(word) }
      }
    }
    return results
  }

  /// Bounded single insertion/deletion/substitution or adjacent transposition.
  /// Two edits and concatenated phrases are deliberately out of scope.
  static func oneEditApart(_ input: String, _ candidate: String) -> Bool {
    let lhs = Array(input), rhs = Array(candidate)
    guard !lhs.isEmpty, abs(lhs.count - rhs.count) <= 1,
          lhs != rhs else { return false }
    if lhs.count == rhs.count {
      let differences = lhs.indices.filter { lhs[$0] != rhs[$0] }
      if differences.count == 1 { return true }
      return differences.count == 2
        && differences[1] == differences[0] + 1
        && lhs[differences[0]] == rhs[differences[1]]
        && lhs[differences[1]] == rhs[differences[0]]
    }
    let longer = lhs.count > rhs.count ? lhs : rhs
    let shorter = lhs.count > rhs.count ? rhs : lhs
    var i = 0, j = 0, skipped = false
    while i < longer.count && j < shorter.count {
      if longer[i] == shorter[j] {
        i += 1
        j += 1
      } else {
        if skipped { return false }
        skipped = true
        i += 1
      }
    }
    return true
  }

  private static func isLatinLetter(_ character: Character) -> Bool {
    !character.unicodeScalars.isEmpty && character.unicodeScalars.allSatisfy { scalar in
      switch scalar.value {
      case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F,
           0x0300...0x036F: return true
      default: return false
      }
    }
  }
}
