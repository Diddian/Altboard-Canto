import Foundation

/// Works with the text that iOS allows a third-party keyboard to inspect.
enum SentenceCapitalization {
  static func shouldUseUppercase(after context: String?) -> Bool {
    guard let context, !context.isEmpty else { return true }
    if let newline = context.lastIndex(where: { $0 == "\n" || $0 == "\r" }) {
      let remaining = context[context.index(after: newline)...]
      if remaining.allSatisfy(\.isWhitespace) { return true }
    }
    guard let last = context.last(where: { !$0.isWhitespace }) else { return true }
    return ".!?。！？".contains(last)
  }
}
