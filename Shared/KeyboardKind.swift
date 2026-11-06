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

/// Only applies to the Microphone Only keyboard. Alphabet and Symbols
/// always use the full, fixed-height layout, independent of legacy sliders.
enum MicrophoneKeyboardLayout: String, CaseIterable, Sendable {
  case defaultLayout = "default"
  case compact

  var displayName: String {
    switch self {
    case .defaultLayout: "Default"
    case .compact: "Compact"
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

/// Romanization changes the offline candidate search, never Latin typing.
enum CantoneseRomanizationScheme: String, CaseIterable, Sendable {
  case jyutping
  case yale
  case yuetyam

  var displayName: String {
    switch self {
    case .jyutping: "Jyutping"
    case .yale: "Yale"
    case .yuetyam: "Yuetyam"
    }
  }
}
