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


/// A complete two-character-or-longer phrase takes priority over the raw
/// romanization. Invalid, incomplete and host-mismatched input stays literal.
enum CantonesePhraseCommitPolicy {
  static func hidesLatinLiteral(firstCandidate: String?,
                                isCurrentComposition: Bool,
                                hasExactEntry: Bool,
                                recognizesLatinWord: Bool = false) -> Bool {
    isCurrentComposition && hasExactEntry && !recognizesLatinWord
      && (firstCandidate?.count ?? 0) >= 2
  }

  static func commitsFirstOnSpace(spelling: String, firstCandidate: String?,
                                  hasExactEntry: Bool, hostMatches: Bool,
                                  recognizesLatinWord: Bool = false) -> Bool {
    !spelling.isEmpty && hasExactEntry && hostMatches
      && hidesLatinLiteral(firstCandidate: firstCandidate,
                           isCurrentComposition: true,
                           hasExactEntry: hasExactEntry,
                           recognizesLatinWord: recognizesLatinWord)
  }
}
