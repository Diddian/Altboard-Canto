import Foundation

/// Side-effect-free quote suggestion based on visible text before the cursor.
/// The keyboard never edits existing host text or assumes it owns the cursor.
enum ChinesePunctuationPolicy {
  static func nextCornerQuote(after context: String) -> String {
    var open = 0
    for character in context {
      switch character {
      case "\n", "\r":
        // A quotation from a previous paragraph must not keep the next
        // paragraph's first quote permanently stuck on closing.
        open = 0
      case "「":
        open += 1
      case "」":
        open = max(0, open - 1)
      default:
        break
      }
    }
    return open == 0 ? "「" : "」"
  }
}
