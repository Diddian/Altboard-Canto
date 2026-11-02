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
