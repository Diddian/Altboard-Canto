import Foundation

/// Pure, testable guard against deleting text that the IME did not just type.
/// The host's UITextDocumentProxy may return a truncated or nil context.
enum LiveCantoneseSafety {
  static func matches(buffer: String, hostContext: String?) -> Bool {
    guard !buffer.isEmpty, let hostContext, hostContext.count >= buffer.count else { return false }
    return hostContext.lowercased().hasSuffix(buffer.lowercased())
  }

  static func canDeleteAsToken(
    buffer: String, candidateCount: Int, hostContext: String?
  ) -> Bool {
    candidateCount > 0 && matches(buffer: buffer, hostContext: hostContext)
  }
}
