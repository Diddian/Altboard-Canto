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
    for parts in spellings {
      if parts.joined() == input { return parts.last?.count }
      // ng is a deliberate colloquial spelling of 唔, not a general
      // substitution for every syllable containing n/g.
      let positions = syllables.enumerated().compactMap {
        $0.element == "m4" ? $0.offset : nil
      }.prefix(3)
      let slots = Array(positions)
      if slots.isEmpty { continue }
      for mask in 1..<(1 << slots.count) {
        var variants = parts
        for (bit, position) in slots.enumerated() where (mask & (1 << bit)) != 0 {
          variants[position] = "ng"
        }
        if variants.joined() == input { return variants.last?.count }
      }
    }
    return nil
  }

  static func sidneyLauAlias(_ syllable: String) -> String {
    let yale = yaleAlias(syllable)
    if yale == "yu" { return "yue" }
    if yale == "yun" { return "yuen" }
    if yale == "yut" { return "yuet" }
    for (old, new) in [
      ("eui", "ui"), ("eun", "un"), ("eut", "ut"),
      ("yun", "uen"), ("yut", "uet"), ("yu", "ue"), ("ou", "o")
    ] {
      if yale.hasSuffix(old) { return String(yale.dropLast(old.count)) + new }
    }
    return yale
  }

  static func yaleAlias(_ syllable: String) -> String {
    var base = syllable.trimmingCharacters(in: CharacterSet(charactersIn: "123456"))
    if base.hasPrefix("jy") { base = "y" + base.dropFirst(2) }
    else if base.hasPrefix("j") { base = "y" + base.dropFirst() }
    else if base.hasPrefix("z") { base = "j" + base.dropFirst() }
    else if base.hasPrefix("c") { base = "ch" + base.dropFirst() }
    return base.replacingOccurrences(of: "oe", with: "eu")
      .replacingOccurrences(of: "eo", with: "eu")
  }
}
