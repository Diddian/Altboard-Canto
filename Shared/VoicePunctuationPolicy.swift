import Foundation

/// Punctuation is controlled at final dictation delivery, after translation.
enum VoicePunctuationPolicy {
  static func render(_ text: String, enabled: Bool) -> String {
    guard !enabled else { return text }
    var result = ""
    result.reserveCapacity(text.utf8.count)
    var pendingSpace = false
    let scalars = text.unicodeScalars
    var previous: Unicode.Scalar?
    var position = scalars.startIndex
    while position < scalars.endIndex {
      let scalar = scalars[position]
      let nextPosition = scalars.index(after: position)
      let following = nextPosition < scalars.endIndex ? scalars[nextPosition] : nil
      let innerApostrophe = (scalar == "'" || scalar == "’")
        && previous.map { CharacterSet.letters.contains($0) } == true
        && following.map { CharacterSet.letters.contains($0) } == true
      let numberSeparator = (scalar == "." || scalar == ",")
        && previous.map { CharacterSet.decimalDigits.contains($0) } == true
        && following.map { CharacterSet.decimalDigits.contains($0) } == true
      if innerApostrophe || numberSeparator {
        if pendingSpace { result.append(" "); pendingSpace = false }
        result.append(String(scalar))
      } else if CharacterSet.punctuationCharacters.contains(scalar)
        || CharacterSet.whitespacesAndNewlines.contains(scalar) {
        if !result.isEmpty { pendingSpace = true }
      } else {
        if pendingSpace { result.append(" "); pendingSpace = false }
        result.append(String(scalar))
      }
      previous = scalar
      position = nextPosition
    }
    return result
  }
}
