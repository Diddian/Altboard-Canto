import Foundation

/// Local Latin long-press choices for the English QWERTZ/QWERTY layout.
enum LetterKeyAlternates {
  static func choices(for letter: String, uppercase: Bool,
                      secondary: String? = nil) -> [String] {
    let key = letter.lowercased()
    let base = uppercase ? letter.uppercased() : key
    let other = (alternates[key] ?? []).map { value -> String in
      if value == "ß" && uppercase { return "ẞ" }
      return uppercase ? value.uppercased() : value
    }
    return [base] + (secondary.map { [$0] } ?? []) + other
  }

  /// Holding must select an alternative, never the original tap character.
  /// A plain tap still inserts the base key via the touch-row's normal path.
  static func holdChoices(for letter: String, uppercase: Bool,
                          secondary: String? = nil) -> [String] {
    Array(choices(for: letter, uppercase: uppercase, secondary: secondary).dropFirst())
  }

  private static let alternates: [String: [String]] = [
    "a": ["à", "á", "â", "ä", "æ", "ã", "å", "ā"],
    "c": ["ç", "ć", "č"], "d": ["ð"],
    "e": ["è", "é", "ê", "ë", "ē", "ė", "ę"],
    "i": ["ì", "í", "î", "ï", "ī", "į"], "l": ["ł"],
    "n": ["ñ", "ń"],
    "o": ["ò", "ó", "ô", "ö", "œ", "õ", "ø", "ō"],
    "s": ["ß", "ś", "š"], "t": ["þ"],
    "u": ["ù", "ú", "û", "ü", "ū"],
    "y": ["ý", "ÿ"], "z": ["ź", "ž", "ż"]
  ]
}

/// Physical-position secondary characters from the first ?123 layout.
/// Accents stay available in the same hold popup.
enum LetterKeySecondary {
  private static let rows: [[String]] = [
    ["1","2","3","4","5","6","7","8","9","0"],
    ["-","/",":",";","(",")","$","&","@"],
    ["\"",".",",","?","!","'","~"]
  ]
  static func symbol(row: Int, index: Int) -> String? {
    guard rows.indices.contains(row), rows[row].indices.contains(index) else { return nil }
    return rows[row][index]
  }
}

/// The first held option is always visually nearest the pressed key.
/// Right-hand popups expand left and display their choices in reverse order,
/// so a leftward finger movement selects a leftward visual option.
enum LetterHoldNavigation {
  static func expandsLeft(column: Int, keyCount: Int) -> Bool {
    column >= keyCount / 2
  }

  static func visualOrder(count: Int, expandsLeft: Bool) -> [Int] {
    guard count > 0 else { return [] }
    let indices = Array(0..<count)
    return expandsLeft ? Array(indices.reversed()) : indices
  }

  static func selectedIndex(initialX: Double, currentX: Double,
                            expandsLeft: Bool, count: Int,
                            step: Double) -> Int {
    guard count > 0, step > 0 else { return 0 }
    let distance = expandsLeft ? initialX - currentX : currentX - initialX
    return min(count - 1, max(0, Int(max(0, distance) / step)))
  }
}
