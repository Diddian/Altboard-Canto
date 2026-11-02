import Foundation

/// Small, deterministic English override without an LLM or a language toggle.
/// This is deliberately narrow: only the common "OK" abbreviation requested.
enum EnglishCaseSuggestion {
  static func replacement(for typed: String) -> String? {
    guard typed.lowercased() == "ok", typed != "OK" else { return nil }
    return "OK"
  }
}
