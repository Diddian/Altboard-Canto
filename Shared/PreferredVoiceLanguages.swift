import Foundation

/// A short user-controlled list for both source-language safeguards and the
/// keyboard's output-language cycle. Qwen3 ONNX does not accept a language
/// lock: source preferences therefore validate its *result*, not its audio.
enum PreferredVoiceLanguages {
  static let legacyChoices = ["yue", "en", "de"]

  static func normalized(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.map { value in
      let lower = value.lowercased()
      if lower == "zh-hk" || lower.hasPrefix("zh-hant-hk") { return "yue" }
      return lower.split(separator: "-").first.map(String.init) ?? ""
    }
      .filter { SpeechLanguages.all.contains($0) && seen.insert($0).inserted }
  }

  struct Choice: Equatable {
    let target: VoiceOutputTarget
    let languageCode: String
    let label: String
  }

  static func choices(from preferred: [String]) -> [Choice] {
    let codes = normalized(preferred)
    return [Choice(target: .original, languageCode: "", label: "AUTO")]
      + codes.map { code in
        let target: VoiceOutputTarget =
          switch code {
          case "yue": .cantonese
          case "zh": .traditionalChinese
          case "en": .english
          case "de": .german
          default: .custom
          }
        let label: String =
          switch code {
          case "yue": "粵"
          case "zh": "繁"
          default: code.uppercased()
          }
        return Choice(target: target, languageCode: code, label: label)
      }
  }

  static func currentCode(target: VoiceOutputTarget, custom: String) -> String {
    switch target {
    case .original: ""
    case .cantonese: "yue"
    case .traditionalChinese: "zh"
    case .english: "en"
    case .german: "de"
    case .custom: custom.lowercased()
    }
  }

  static func next(target: VoiceOutputTarget, custom: String, preferred: [String]) -> Choice {
    let options = choices(from: preferred)
    let current = currentCode(target: target, custom: custom)
    guard let index = options.firstIndex(where: { $0.languageCode == current }) else {
      return options[0]
    }
    return options[(index + 1) % options.count]
  }

  /// Reject an obviously unrelated writing system before translating or
  /// inserting text. Do not pretend to reconstruct the intended speech.
  static func unexpectedScript(in text: String, allowed: [String]) -> String? {
    let codes = Set(normalized(allowed))
    guard !codes.isEmpty else { return nil } // "Any language"
    let scalars = Array(text.unicodeScalars)
    let scripts: [(code: String, range: ClosedRange<UInt32>)] = [
      ("th", 0x0E00...0x0E7F),
      ("ar", 0x0600...0x06FF),
      ("ru", 0x0400...0x04FF),
      ("hi", 0x0900...0x097F),
      ("ko", 0xAC00...0xD7AF),
      ("ja", 0x3040...0x30FF)
    ]
    // Chinese characters are shared across Cantonese, Mandarin, Japanese.
    // Reject them only when the user chose exclusively non-Han languages.
    let acceptsHan = !codes.isDisjoint(with: ["yue", "zh", "ja"])
    let han = scalars.filter { (0x3400...0x9FFF).contains($0.value) }.count
    if !acceptsHan && han >= 3 && han * 6 > scalars.count { return "zh" }

    for script in scripts {
      if codes.contains(script.code) { continue }
      // Japanese syllabaries aren't used in everyday Cantonese; Han
      // characters alone are shared across zh/yue/ja and cannot identify it.
      let count = scalars.filter { script.range.contains($0.value) }.count
      if count >= 3 && count * 6 > scalars.count { return script.code }
    }
    return nil
  }
}
