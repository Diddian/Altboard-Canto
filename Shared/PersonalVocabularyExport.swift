import Foundation

/// Export only bounded aggregate choice counts. No typed context or host text.
enum PersonalVocabularyExport {
  /// Only explicit user corrections are exported. No full audio or host text.
  struct CorrectionEntry: Encodable {
    let language: String
    let heard: String
    let intended: String
  }

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
    let manualSpeechCorrections: [CorrectionEntry]
  }

  static func encode(cantonese: [String: Int], latin: [String: Int],
                     romanization: [String: Int], confirmedChinese: [String: Int] = [:],
                     shapes: [String: Int] = [:], shapeGenerations: [String: Int] = [:],
                     strokePrefixes: [String: Int] = [:],
                     manualCorrections: [CorrectionEntry] = []) throws -> Data {
    func bounded(_ counts: [String: Int]) -> [String: Int] {
      Dictionary(uniqueKeysWithValues: counts.compactMap { key, value in
        guard (1...128).contains(key.count), (1...10_000).contains(value) else { return nil }
        return (key, value)
      })
    }
    let corrected = Array(manualCorrections.filter {
      ["yue", "en", "de"].contains($0.language)
        && (1...80).contains($0.heard.count)
        && (1...80).contains($0.intended.count)
        && $0.heard != $0.intended
    }.prefix(90))
    let payload = Payload(schemaVersion: 3, cantoneseSelections: bounded(cantonese),
                          latinSelections: bounded(latin),
                          romanizationPreferenceCounts: bounded(romanization),
                          confirmedChineseWords: bounded(confirmedChinese),
                          shapeSelections: bounded(shapes),
                          shapeGenerationPreferences: bounded(shapeGenerations),
                          strokePrefixSelections: bounded(strokePrefixes),
                          manualSpeechCorrections: corrected)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(payload)
  }
}
