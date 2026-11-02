import Foundation

/// Preserve original raw values so existing installations retain their mode.
enum KeyboardKind: String, CaseIterable, Sendable {
  case standard
  case extended
  case alphabetic

  var displayNameKey: String {
    switch self {
    case .standard: "Microphone Only"
    case .extended: "Symbols"
    case .alphabetic: "Alphabet"
    }
  }
}

/// A QWERTZ-first English typing layout, with optional QWERTY ordering.
enum LetterKeyArrangement: String, CaseIterable, Sendable {
  case qwertz
  case qwerty

  var rows: [[String]] {
    switch self {
    case .qwertz:
      [["Q","W","E","R","T","Z","U","I","O","P"],
       ["A","S","D","F","G","H","J","K","L"],
       ["Y","X","C","V","B","N","M"]]
    case .qwerty:
      [["Q","W","E","R","T","Y","U","I","O","P"],
       ["A","S","D","F","G","H","J","K","L"],
       ["Z","X","C","V","B","N","M"]]
    }
  }
}

enum KeyboardTypingLanguage: String, CaseIterable, Sendable {
  case english
  case jyutping
}
