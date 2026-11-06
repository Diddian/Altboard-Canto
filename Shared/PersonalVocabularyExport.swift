import Foundation

// Contains only explicitly selected aggregate candidates and manual corrections.
// No keyboard text, host context, audio, transcripts or credentials.
enum PersonalVocabularyExport {
  struct CorrectionEntry: Encodable {
    let language: String
    let heard: String
    let intended: String
  }
  private struct Payload: Encodable {
    let schemaVersion: Int
    let appVersion: String
    let appBuild: String
    let appCommit: String
    let keyboardCommit: String
    let selections: [String: Int]
    let romanizationPreferences: [String: Int]
    let manualSpeechCorrections: [CorrectionEntry]
    let unavailable: [String]
  }
  static func encode(selections: [String: Int], romanization: [String: Int],
                     corrections: [CorrectionEntry],
                     version: String, build: String, commit: String,
                     keyboardCommit: String) throws -> Data {
    func bounded(_ counts: [String: Int]) -> [String: Int] {
      Dictionary(uniqueKeysWithValues: counts.compactMap { key, value in
        guard (1...128).contains(key.count), (1...10_000).contains(value) else { return nil }
        return (key, value)
      })
    }
    let safeCorrections = Array(corrections.filter {
      $0.language == "yue" && (1...80).contains($0.heard.count)
        && (1...80).contains($0.intended.count) && $0.heard != $0.intended
    }.prefix(50))
    let payload = Payload(
      schemaVersion: 1, appVersion: version, appBuild: build, appCommit: commit,
      keyboardCommit: keyboardCommit, selections: bounded(selections),
      romanizationPreferences: bounded(romanization),
      manualSpeechCorrections: safeCorrections,
      unavailable: ["laterLatinLearning", "confirmedChoiceLearning", "laterWeightedPreference"])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(payload)
  }
}
