import Foundation

/// Transient word context for reviewed EN/DE and code-switch seed predictions.
/// Nothing here persists host text; the caller may use only its last two tokens.
enum InformalNgramPolicy {
  static func tokens(in context: String?) -> [String] {
    guard let context else { return [] }
    var result = [String]()
    var word = ""
    func flush() {
      if !word.isEmpty { result.append(word.lowercased()); word = "" }
    }
    for character in context.suffix(120) {
      let code = character.unicodeScalars.first?.value ?? 0
      let han = (0x3400...0x9FFF).contains(code) || (0x20000...0x323AF).contains(code)
      if han {
        flush()
        result.append(String(character))
      } else if character.isLetter || character.isNumber {
        word.append(character)
      } else if (character == "'" || character == "’") && !word.isEmpty {
        word.append("'")
      } else {
        flush()
        if ".!?。！？\n\r".contains(character) { result.removeAll() }
      }
    }
    flush()
    return Array(result.suffix(3))
  }

  static func preceding(in context: String?, current: String? = nil) -> [String] {
    guard var context else { return [] }
    if let current, !current.isEmpty, context.hasSuffix(current) {
      context.removeLast(current.count)
    }
    return Array(tokens(in: context).suffix(2))
  }

  static func histories(for tokens: [String]) -> [String] {
    guard let last = tokens.last else { return [] }
    if tokens.count >= 2 {
      return [tokens.suffix(2).joined(separator: " "), last]
    }
    return [last]
  }
}
