import Foundation

/// Export only bounded aggregate choice counts. No typed context or host text.
enum PersonalVocabularyExport {
  private struct Payload: Encodable {
    let schemaVersion: Int
    let cantoneseSelections: [String: Int]
    let latinSelections: [String: Int]
    let romanizationPreferenceCounts: [String: Int]
    let confirmedChineseWords: [String: Int]
    let shapeSelections: [String: Int]
    let shapeGenerationPreferences: [String: Int]
    // Stroke-prefix keys arise from explicitly selected character codes,
    // never from raw touch paths or uncommitted host text.
    let strokePrefixSelections: [String: Int]
  }

  static func encode(cantonese: [String: Int], latin: [String: Int],
                     romanization: [String: Int], confirmedChinese: [String: Int] = [:],
                     shapes: [String: Int] = [:], shapeGenerations: [String: Int] = [:],
                     strokePrefixes: [String: Int] = [:]) throws -> Data {
    func bounded(_ counts: [String: Int]) -> [String: Int] {
      Dictionary(uniqueKeysWithValues: counts.compactMap { key, value in
        guard (1...128).contains(key.count), (1...10_000).contains(value) else { return nil }
        return (key, value)
      })
    }
    let payload = Payload(schemaVersion: 2, cantoneseSelections: bounded(cantonese),
                          latinSelections: bounded(latin),
                          romanizationPreferenceCounts: bounded(romanization),
                          confirmedChineseWords: bounded(confirmedChinese),
                          shapeSelections: bounded(shapes),
                          shapeGenerationPreferences: bounded(shapeGenerations),
                          strokePrefixSelections: bounded(strokePrefixes))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(payload)
  }
}
