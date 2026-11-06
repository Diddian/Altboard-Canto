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
      // Only a terminal optional vowel+h is accepted as a suffix of the
      // last confirmed syllable (nah, woh, goh). Delete both together.
      if let tail = parts.last, let lastLetter = tail.last,
         "aeiou".contains(lastLetter),
         parts.joined() + "h" == input {
        return tail.count + 1
      }
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

  // Keep conversion identical to the pinned SQLite builder. A long -aa
  // open syllable is written -a in Yale/Sidney, but -aan/-aam/-aak retain aa.
  private static let finals: Set<String> = Set(
    ("aa aai aau aam aan aang aap aat aak ai au am an ang ap at ak " +
    "e ei eu em en eng ep et ek eoi eon eot " +
    "i iu im in ing ip it ik " +
    "o oi on ong ok ot ou oe oeng oek oet " +
    "u ui un ung uk um up ut yu yun yut m ng")
      .split(separator: " ").map(String.init)
  )
  private static let onsets = [
    "gw", "kw", "ng", "b", "p", "m", "f", "d", "t", "n", "l",
    "g", "k", "h", "z", "c", "s", "j", "w"
  ]
  private static let yaleFinals = [
    "aa": "a", "oe": "eu", "oeng": "eung",
    "oek": "euk", "oet": "eut",
    "eoi": "eui", "eon": "eun", "eot": "eut"
  ]
  private static let sidneyFinals = [
    "aa": "a", "oe": "euh", "oeng": "eung",
    "oek": "euk", "oet": "eut",
    "eoi": "ui", "eon": "un", "eot": "ut",
    "o": "oh", "ou": "o", "u": "oo", "ui": "ooi",
    "un": "oon", "ut": "oot", "yu": "ue",
    "yun": "uen", "yut": "uet"
  ]

  static func sidneyLauAlias(_ syllable: String) -> String {
    self.traditionalAlias(syllable, finals: self.sidneyFinals, sidney: true)
  }

  static func yaleAlias(_ syllable: String) -> String {
    self.traditionalAlias(syllable, finals: self.yaleFinals, sidney: false)
  }

  private static func traditionalAlias(
    _ syllable: String, finals: [String: String], sidney: Bool
  ) -> String {
    let input = syllable.trimmingCharacters(in: CharacterSet(charactersIn: "123456"))
    let onsetAndFinal: (String, String)?
    if input == "m" || input == "ng" {
      onsetAndFinal = ("", input)
    } else {
      onsetAndFinal = self.onsets.compactMap { onset -> (String, String)? in
        guard input.hasPrefix(onset) else { return nil }
        let final = String(input.dropFirst(onset.count))
        return self.finals.contains(final) ? (onset, final) : nil
      }.first
    }
    guard let components = onsetAndFinal, self.finals.contains(components.1)
    else { return input }
    let onset = components.0
    let final = components.1
    let mappedFinal = finals[final] ?? final
    if onset == "j" && final.hasPrefix("yu") {
      return sidney ? "y" + mappedFinal : mappedFinal
    }
    let mappedOnset: String
    switch onset {
    case "z": mappedOnset = "j"
    case "c": mappedOnset = "ch"
    case "j": mappedOnset = "y"
    default: mappedOnset = onset
    }
    return mappedOnset + mappedFinal
  }
}
