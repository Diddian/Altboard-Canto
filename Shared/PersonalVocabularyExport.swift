import Foundation

/// Export only bounded aggregate choice counts. No typed context or host text.
enum PersonalVocabularyExport {
  private struct Payload: Encodable {
    let schemaVersion: Int
    let cantoneseSelections: [String: Int]
    let latinSelections: [String: Int]
    let romanizationPreferenceCounts: [String: Int]
  }

  static func encode(cantonese: [String: Int], latin: [String: Int],
                     romanization: [String: Int]) throws -> Data {
    func bounded(_ counts: [String: Int]) -> [String: Int] {
      Dictionary(uniqueKeysWithValues: counts.compactMap { key, value in
        guard (1...128).contains(key.count), (1...10_000).contains(value) else { return nil }
        return (key, value)
      })
    }
    let payload = Payload(schemaVersion: 1, cantoneseSelections: bounded(cantonese),
                          latinSelections: bounded(latin),
                          romanizationPreferenceCounts: bounded(romanization))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(payload)
  }
}
