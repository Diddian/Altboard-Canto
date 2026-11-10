import Foundation

/// A short user-controlled list for both source-language safeguards and the
/// keyboard's output-language cycle. Qwen3 ONNX does not accept a language
/// lock: source preferences therefore validate its *result*, not its audio.
enum PreferredVoiceLanguages {
  static let legacyChoices = ["yue", "en", "de"]

  static func normalized(_ values: [String]) -> [String] {
    LanguagePriority.ordered(values, available: SpeechLanguages.all)
  }

  struct Choice: Equatable {
    let target: VoiceOutputTarget
    let languageCode: String
    let label: String
  }

  /// Use the language's own writing system where a short label is meaningful.
  static func shortLabel(for code: String) -> String {
    // Spoken Mandarin ("zh") is not the same as Traditional written output.
    // Codes using Latin script retain their native ISO abbreviations.
    switch LanguagePriority.code(code) {
    case "yue": "粵"
    case "zh": "普"
    case "ja": "日"
    case "ko": "한"
    case "ru": "РУ"
    case "uk": "УК"
    case "be": "БЕ"
    case "bg": "БГ"
    case "sr": "СР"
    case "mk": "МК"
    case "mn": "МН"
    case "kk": "ҚА"
    case "el": "ΕΛ"
    case "ar": "عر"
    case "fa": "فا"
    case "he": "עב"
    case "ur": "ارد"
    case "ps": "پښ"
    case "sd": "سن"
    case "hi": "हि"
    case "ne": "ने"
    case "mr": "मर"
    case "sa": "सं"
    case "bn": "বা"
    case "as": "অসম"
    case "gu": "ગુ"
    case "pa": "ਪੰ"
    case "ta": "த"
    case "te": "తె"
    case "ml": "മ"
    case "kn": "ಕ"
    case "si": "සි"
    case "th": "ไทย"
    case "lo": "ລາວ"
    case "km": "ខ្មែរ"
    case "my": "မြန်"
    case "am": "አማ"
    case "hy": "ՀՅ"
    case "ka": "ქა"
    case "bo": "བོད"
    case "yi": "יי"
    default: LanguagePriority.code(code).uppercased()
    }
  }

  /// Spoken-language preference and output-script labels have different meanings.
  static func outputShortLabel(for code: String) -> String {
    let value = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if ["zh-hans", "zh-cn", "zh-sg"].contains(value) { return "简" }
    if ["zh", "zh-hant", "zh-hk", "zh-tw"].contains(value) { return "繁" }
    if ["yue", "yue-hk"].contains(value) { return "粵" }
    return shortLabel(for: code)
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
        let label = target == .traditionalChinese ? target.keyboardLabel : shortLabel(for: code)
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

