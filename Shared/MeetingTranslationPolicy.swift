import Foundation

/// Deterministic bounded input for offline meeting translation. This is not
/// a model tokenizer: short chunks leave room for the system prompt and output.
enum MeetingTranslationPolicy {
  static let maximumChunkCharacters = 180

  static func chunks(_ text: String) -> [String] {
    let characters = Array(text)
    guard !characters.isEmpty else { return [] }
    var output = [String]()
    var start = 0

    while start < characters.count {
      var end = min(start + maximumChunkCharacters, characters.count)
      if end < characters.count {
        let earliest = start + maximumChunkCharacters / 2
        if earliest < end,
           let boundary = (earliest..<end).last(where: {
             characters[$0].isWhitespace || ".!?。！？；;".contains(characters[$0])
           }) {
          end = boundary + 1
        }
      }
      let chunk = String(characters[start..<end])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !chunk.isEmpty { output.append(chunk) }
      start = end
    }
    return output
  }

  /// Stable nonsecret change detector, not a cryptographic security boundary.
  /// Stored only alongside the already-saved raw transcript in the App Group.
  static func sourceFingerprint(_ text: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in text.utf8 {
      hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
    }
    return String(hash, radix: 16)
  }

  static func canResume(
    sourceFingerprint: String, configurationKey: String,
    savedFingerprint: String?, savedConfigurationKey: String?,
    processedChunks: Int?, totalChunks: Int, savedTranslation: String?
  ) -> Bool {
    guard totalChunks > 0,
          savedFingerprint == sourceFingerprint,
          savedConfigurationKey == configurationKey,
          let processedChunks, processedChunks >= 0,
          processedChunks <= totalChunks else { return false }
    return processedChunks == 0 || !(savedTranslation ?? "").isEmpty
  }

  static func hasMatchingSavedOutput(
    _ saved: String?, savedLanguage: String?, targetLanguage: String
  ) -> Bool {
    savedLanguage == targetLanguage && !(saved ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  static func combined(_ current: String?, next: String) -> String {
    let clean = next.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return current ?? "" }
    guard let current, !current.isEmpty else { return clean }
    return current + "\n" + clean
  }
}
