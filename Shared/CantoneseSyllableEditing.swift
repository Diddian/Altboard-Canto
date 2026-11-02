import Foundation

/// A phonetic suffix is only deleted by syllable when it is an exact match
/// for a complete offline lexicon entry. Unknown English remains characterwise.
enum CantoneseSyllableEditing {
  static func lastSyllableLength(typed: String, canonical: String) -> Int? {
    let input = typed.lowercased()
    let syllables = canonical.lowercased().split(separator: " ").map(String.init)
    guard !input.isEmpty, !syllables.isEmpty else { return nil }
    let jyutping = syllables.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "123456")) }
    let yale = syllables.map(yaleAlias)
    let sidneyLau = syllables.map(sidneyLauAlias)
    let spellings = [syllables, jyutping, yale, sidneyLau]
    for parts in spellings where parts.joined() == input {
      guard let last = parts.last, !last.isEmpty else { return nil }
      return last.count
    }
    return nil
  }

  static func sidneyLauAlias(_ syllable: String) -> String {
    let yale = yaleAlias(syllable)
    if yale.hasPrefix("yu") { return "yue" + yale.dropFirst(2) }
    return yale.replacingOccurrences(of: "eui", with: "ui")
      .replacingOccurrences(of: "eun", with: "un")
      .replacingOccurrences(of: "eut", with: "ut")
      .replacingOccurrences(of: "yu", with: "ue")
      .replacingOccurrences(of: "ou", with: "o")
  }

  static func yaleAlias(_ syllable: String) -> String {
    var base = syllable.trimmingCharacters(in: CharacterSet(charactersIn: "123456"))
    if base.hasPrefix("j") { base = "y" + base.dropFirst() }
    else if base.hasPrefix("z") { base = "j" + base.dropFirst() }
    else if base.hasPrefix("c") { base = "ch" + base.dropFirst() }
    return base.replacingOccurrences(of: "oe", with: "eu")
      .replacingOccurrences(of: "eo", with: "eu")
      .replacingOccurrences(of: "aa", with: "a")
  }
}
