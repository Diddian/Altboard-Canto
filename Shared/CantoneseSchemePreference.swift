import Foundation

/// Bounded, explicit-choice-only evidence for romanization ordering.
enum CantoneseSchemePreference {
  static let keys = ["plain", "yale", "sidney"]
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
    return matching.count == 1 ? matching[0] : nil
  }

  static func preferred(_ counts: [String: Int]) -> String? {
    let total = keys.reduce(0) { $0 + (counts[$1] ?? 0) }
    guard total >= 12 else { return nil }
    let ranked = keys.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    let first = counts[ranked[0]] ?? 0
    let second = counts[ranked[1]] ?? 0
    guard first >= 7, first - second >= 4, first * 100 >= total * 55 else { return nil }
    return ranked[0]
  }
}
