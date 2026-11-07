import Foundation

/// Punctuation is controlled at final dictation delivery, after translation.
enum VoicePunctuationPolicy {
  static func render(_ text: String, enabled: Bool) -> String {
    guard !enabled else { return text }
    var result = ""
    result.reserveCapacity(text.utf8.count)
    var pendingSpace = false
    for scalar in text.unicodeScalars {
      if CharacterSet.punctuationCharacters.contains(scalar)
        || CharacterSet.whitespacesAndNewlines.contains(scalar) {
        if !result.isEmpty { pendingSpace = true }
      } else {
        if pendingSpace { result.append(" "); pendingSpace = false }
        result.append(String(scalar))
      }
    }
    return result
  }
}
