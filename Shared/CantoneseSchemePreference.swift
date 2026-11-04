import Foundation

/// Bounded, explicit-choice-only evidence for romanization ordering.
enum CantoneseSchemePreference {
  static let keys = ["plain", "yale", "sidney"]
  static let traditionalKey = "traditional"
  static let colloquialNgKey = "negative_ng"
  static let canonicalMKey = "negative_m"
  static let evidenceKeys = keys + [traditionalKey, colloquialNgKey, canonicalMKey]

  /// Keep evidence local and bounded. Older confirmed selections gradually
  /// lose weight so a user can change spelling habits without a reset.
  static func recordingSelection(
    in counts: [String: Int], typed: String, canonical: String
  ) -> [String: Int] {
    let scheme = inferredScheme(input: typed, canonical: canonical)
    let negative = negativeParticleStyle(input: typed, canonical: canonical)
    guard scheme != nil || negative != nil else { return counts }
    var updated = counts
    if evidenceKeys.reduce(0, { $0 + max(0, updated[$1] ?? 0) }) >= 48 {
      for key in evidenceKeys { updated[key] = max(0, updated[key] ?? 0) / 2 }
    }
    for key in [scheme, negative].compactMap({ $0 }) {
      updated[key] = min(64, max(0, updated[key] ?? 0) + 1)
    }
    return updated
  }

  static func lookupOrder(_ counts: [String: Int]) -> [String] {
    switch preferred(counts) {
    case "yale": return ["yale", "sidney", "plain"]
    case "sidney": return ["sidney", "yale", "plain"]
    default: return keys
    }
  }

  static func prefersColloquialNg(_ counts: [String: Int]) -> Bool {
    let ng = max(0, counts[colloquialNgKey] ?? 0)
    let m = max(0, counts[canonicalMKey] ?? 0)
    return ng >= 3 && ng > m + 1
  }

  /// Only classify ng as 唔 when a confirmed candidate has an m4 syllable.
  /// Matching whole syllable sequences avoids rewriting ng in unrelated words.
  static func negativeParticleStyle(input: String, canonical: String) -> String? {
    let typed = input.lowercased()
    guard !typed.isEmpty, !typed.contains(where: \.isNumber) else { return nil }
    let syllables = canonical.lowercased().split(separator: " ").map(String.init)
    let positions = Array(syllables.indices.filter { syllables[$0] == "m4" }.prefix(4))
    guard !positions.isEmpty else { return nil }
    let partsByScheme = [
      syllables.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "123456")) },
      syllables.map(CantoneseSyllableEditing.yaleAlias),
      syllables.map(CantoneseSyllableEditing.sidneyLauAlias)
    ]
    for parts in partsByScheme {
      if parts.joined() == typed { return canonicalMKey }
      for mask in 1..<(1 << positions.count) {
        var withNg = parts
        for (bit, index) in positions.enumerated() where (mask & (1 << bit)) != 0 {
          withNg[index] = "ng"
        }
        if withNg.joined() == typed { return colloquialNgKey }
      }
    }
    return nil
  }
  static func inferredScheme(
    input: String, canonical: String
  ) -> String? {
    let typed = input.lowercased()
    guard !typed.isEmpty, !typed.contains(where: \.isNumber) else { return nil }
    let syllables = canonical.split(separator: " ").map(String.init)
    let variants = [
      "plain": syllables.map {
        $0.trimmingCharacters(in: CharacterSet(charactersIn: "123456"))
      }.joined(),
      "yale": syllables.map(CantoneseSyllableEditing.yaleAlias).joined(),
      "sidney": syllables.map(CantoneseSyllableEditing.sidneyLauAlias).joined()
    ]
    let matching = keys.filter { variants[$0] == typed }
    if matching.count == 1 { return matching[0] }
    // j- and ch- are shared by Yale and Sidney Lau. Record their
    // common family without pretending that they distinguish the two.
    if matching.count == 2 && matching.contains("yale")
      && matching.contains("sidney") { return traditionalKey }
    return nil
  }

  static func preferred(_ counts: [String: Int]) -> String? {
    let plain = counts["plain"] ?? 0
    let yale = counts["yale"] ?? 0
    let sidney = counts["sidney"] ?? 0
    let traditional = counts[traditionalKey] ?? 0
    let traditionalEvidence = traditional + yale + sidney

    // j/ch are shared by Yale and Sidney Lau; four explicit traditional
    // selections may prefer that family without asserting a specific scheme.
    if traditional >= 4 && traditionalEvidence > plain + 2 {
      return sidney > yale ? "sidney" : "yale"
    }

    let total = plain + yale + sidney
    guard total >= 12 else { return nil }
    let ranked = keys.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    let first = counts[ranked[0]] ?? 0
    let second = counts[ranked[1]] ?? 0
    guard first >= 7, first - second >= 4, first * 100 >= total * 55 else { return nil }
    return ranked[0]
  }
}
