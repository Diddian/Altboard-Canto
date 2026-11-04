import Foundation

/// A small, local-only bridge between confirmed Cantonese selections.
/// Phonetic, Quick, Cangjie and stroke keep their own code-specific evidence;
/// only a chosen Han word is shared. No host text, touch paths or ASR audio.
enum ConfirmedChoiceLearning {
  static let chineseKey = "canto.ime.confirmedChineseChoices.v1"
  static let shapeWordKey = "canto.ime.shapeWordCounts.v1"
  static let shapeGenerationKey = "canto.ime.shapeGenerationCounts.v1"
  static let strokePrefixKey = "canto.ime.strokePrefixSelections.v1"
  static let latinKey = "canto.latin.selectedSuggestions"

  static func increment(
    _ key: String, in previous: [String: Int],
    maximum: Int = 10_000, trimAt: Int = 1_200,
    retain: Int = 600, ageAtTotal: Int = 4_096
  ) -> [String: Int] {
    guard !key.isEmpty, key.count <= 160 else { return previous }
    var counts = previous.filter { $0.value > 0 && !$0.key.isEmpty }
    if counts.values.reduce(0, +) >= ageAtTotal {
      counts = counts.compactMapValues { value in
        let aged = value / 2
        return aged > 0 ? aged : nil
      }
    }
    counts[key] = min(maximum, (counts[key] ?? 0) + 1)
    if counts.count > trimAt {
      counts = Dictionary(uniqueKeysWithValues: counts.sorted {
        $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
      }.prefix(retain).map { ($0.key, $0.value) })
    }
    return counts
  }

  static func chineseCounts(defaults: UserDefaults?) -> [String: Int] {
    defaults?.dictionary(forKey: chineseKey) as? [String: Int] ?? [:]
  }

  @discardableResult
  static func rememberConfirmedChinese(_ text: String, defaults: UserDefaults?) -> Bool {
    guard let defaults, (1...10).contains(text.count),
          text == "の" || text.allSatisfy({ character in
            character.unicodeScalars.allSatisfy { scalar in
              (0x3400...0x9FFF).contains(scalar.value)
                || (0x20000...0x323AF).contains(scalar.value)
            }
          }) else { return false }
    let updated = increment(
      text, in: chineseCounts(defaults: defaults),
      maximum: 96, trimAt: 512, retain: 256, ageAtTotal: 640
    )
    defaults.set(updated, forKey: chineseKey)
    return true
  }

  static func chinesePreference(_ text: String, counts: [String: Int]) -> Int {
    min(8, max(0, counts[text] ?? 0))
  }
}
