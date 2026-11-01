import Foundation

/// Formats unambiguous technical quantities after ASR and optional translation.
/// Does not correct acoustic recognition errors or infer missing digits.
enum TechnicalTextFormatter {
  static func format(_ input: String) -> String {
    guard !input.isEmpty else { return input }
    var result = input
    let matches = self.quantityRegex.matches(
      in: input,
      range: NSRange(input.startIndex..., in: input)
    )
    for match in matches.reversed() {
      guard let quantityRange = Range(match.range, in: result),
            let numberRange = Range(match.range(at: 1), in: result),
            let unitRange = Range(match.range(at: 2), in: result),
            let amount = self.numericText(String(result[numberRange])),
            let abbreviation = self.abbreviations[String(result[unitRange]).lowercased()]
      else { continue }
      result.replaceSubrange(quantityRange, with: "\(amount) \(abbreviation)")
    }
    return result
  }

  private static let singleDigits: [String: Int] = [
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4,
    "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    "null": 0, "ein": 1, "eins": 1, "zwei": 2, "drei": 3,
    "vier": 4, "fünf": 5, "fuenf": 5, "funf": 5, "sechs": 6,
    "sieben": 7, "acht": 8, "neun": 9
  ]

  private static let englishCounts: [String: Int] = [
    "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
    "fourteen": 14, "fifteen": 15, "sixteen": 16,
    "seventeen": 17, "eighteen": 18, "nineteen": 19,
    "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
    "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
  ]

  private static let chineseDigits: [Character: String] = [
    "零": "0", "〇": "0", "一": "1", "二": "2", "兩": "2",
    "三": "3", "四": "4", "五": "5", "六": "6", "七": "7",
    "八": "8", "九": "9"
  ]

  private static let abbreviations: [String: String] = [
    "kilobyte": "KB", "kilobytes": "KB",
    "megabyte": "MB", "megabytes": "MB",
    "gigabyte": "GB", "gigabytes": "GB",
    "terabyte": "TB", "terabytes": "TB",
    "kilobit": "Kb", "kilobits": "Kb",
    "megabit": "Mb", "megabits": "Mb",
    "gigabit": "Gb", "gigabits": "Gb",
    "terabit": "Tb", "terabits": "Tb",
    "kilohertz": "kHz", "megahertz": "MHz",
    "gigahertz": "GHz",
    "kb": "KB", "mb": "MB", "gb": "GB", "tb": "TB",
    "khz": "kHz", "mhz": "MHz", "ghz": "GHz"
  ]

  private static let quantityRegex: NSRegularExpression = {
    let digit = #"(?:zero|one|two|three|four|five|six|seven|eight|nine|null|ein|eins|zwei|drei|vier|fünf|fuenf|funf|sechs|sieben|acht|neun)"#
    let tens = #"(?:twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)"#
    let teens = #"(?:ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen)"#
    let whole = "(?:\(tens)(?:[- ]\(digit))?|\(teens)|\(digit))"
    let decimalDigits = "(?:\(digit)|[0-9])"
    let decimal = "(?:[0-9]+|\(whole))\\s+(?:point|dot|comma|komma)\\s+\(decimalDigits)(?:\\s+\(decimalDigits))*"
    let chinese = #"[零〇一二兩三四五六七八九]+(?:[點点][零〇一二兩三四五六七八九]+)?"#
    let number = "(?:[0-9]+(?:[.,][0-9]+)?|\(decimal)|\(whole)|\(chinese))"
    let units = "(?:" + abbreviations.keys
      .sorted { $0.count > $1.count }
      .map { NSRegularExpression.escapedPattern(for: $0) }
      .joined(separator: "|") + ")"
    // Avoid matching a number inside an English identifier. Cantonese may
    // attach unit quantities directly to surrounding Chinese characters.
    return try! NSRegularExpression(
      pattern: "(?<![A-Za-z0-9])(\(number))\\s*(\(units))(?![A-Za-z])",
      options: [.caseInsensitive]
    )
  }()

  private static func numericText(_ phrase: String) -> String? {
    let input = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
    if input.range(of: #"^[0-9]+(?:[.,][0-9]+)?$"#, options: .regularExpression) != nil {
      return input.replacingOccurrences(of: ",", with: ".")
    }

    if input.allSatisfy({ chineseDigits[$0] != nil || $0 == "點" || $0 == "点" }) {
      let pieces = input.replacingOccurrences(of: "点", with: "點").split(separator: "點")
      guard !pieces.isEmpty, pieces.count <= 2,
            pieces.allSatisfy({ !$0.isEmpty }) else { return nil }
      return pieces.map { component in
        String(component.compactMap { chineseDigits[$0] }.joined())
      }.joined(separator: ".")
    }

    let lower = input.lowercased().replacingOccurrences(of: "-", with: " ")
    for marker in [" point ", " dot ", " comma ", " komma "] {
      guard let range = lower.range(of: marker) else { continue }
      let whole = String(lower[..<range.lowerBound])
      let fractions = lower[range.upperBound...].split(separator: " ")
      guard let integer = integerValue(whole), !fractions.isEmpty else { return nil }
      var digits = ""
      for fraction in fractions {
        if let raw = Int(fraction), (0...9).contains(raw) {
          digits += String(raw)
        } else if let value = singleDigits[String(fraction)] {
          digits += String(value)
        } else {
          return nil
        }
      }
      return "\(integer).\(digits)"
    }
    return integerValue(lower).map(String.init)
  }

  private static func integerValue(_ text: String) -> Int? {
    if let number = Int(text) { return number }
    let parts = text.split(separator: " ").map(String.init)
    guard !parts.isEmpty else { return nil }
    if parts.count == 1 {
      return singleDigits[parts[0]] ?? englishCounts[parts[0]]
    }
    guard parts.count == 2,
          let tens = englishCounts[parts[0]], tens >= 20,
          let units = singleDigits[parts[1]], (1...9).contains(units)
    else { return nil }
    return tens + units
  }
}
