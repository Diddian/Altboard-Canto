import Foundation

/// Bounded, explicit-choice-only evidence for romanization ordering.
enum CantoneseSchemePreference {
  static let keys = ["plain", "yale", "sidney"]
  static let traditionalKey = "traditional"
  static let evidenceKeys = keys + [traditionalKey]
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
