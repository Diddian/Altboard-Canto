import Foundation

/// A short, localized listening indicator. It never changes transcription,
/// output language, recording state or the original/final text.
enum LiveDictationNotice {
  private static let listening: [String: String] = [
    "en": "Listening…",
    "bg": "Слушам…",
    "cs": "Poslouchám…",
    "da": "Lytter…",
    "de": "Höre zu…",
    "el": "Ακούω…",
    "es": "Escuchando…",
    "et": "Kuulan…",
    "fi": "Kuuntelen…",
    "fr": "J’écoute…",
    "hi": "सुन रहे हैं…",
    "hr": "Slušam…",
    "hu": "Figyelek…",
    "it": "In ascolto…",
    "ja": "聞き取り中…",
    "ko": "듣는 중…",
    "lt": "Klausoma…",
    "lv": "Klausās…",
    "nl": "Luistert…",
    "no": "Lytter…",
    "pl": "Słucham…",
    "pt": "A ouvir…",
    "ro": "Ascult…",
    "ru": "Слушаю…",
    "sk": "Počúvam…",
    "sl": "Poslušam…",
    "sv": "Lyssnar…",
    "tr": "Dinleniyor…",
    "uk": "Слухаю…",
    "zh-Hant": "聆聽中…",
    "zh-Hans": "聆听中…",
  ]

  private static let afterwards: [String: String] = [
    "en": "tidy afterwards",
    "bg": "после се изглажда",
    "cs": "poté se upraví",
    "da": "rettes bagefter",
    "de": "danach überarbeiten",
    "el": "διόρθωση μετά",
    "es": "pulir después",
    "et": "hiljem korrigeerida",
    "fi": "siistitään myöhemmin",
    "fr": "corriger ensuite",
    "hi": "बाद में सुधार",
    "hr": "uredi poslije",
    "hu": "utólag javítjuk",
    "it": "rifinire dopo",
    "ja": "後で整えます",
    "ko": "나중에 다듬기",
    "lt": "vėliau pataisoma",
    "lv": "vēlāk izlabo",
    "nl": "later bijwerken",
    "no": "ryddes etterpå",
    "pl": "później poprawimy",
    "pt": "rever depois",
    "ro": "corectăm după",
    "ru": "позже исправим",
    "sk": "neskôr upraviť",
    "sl": "uredi pozneje",
    "sv": "rensas efteråt",
    "tr": "sonra düzenlenir",
    "uk": "пізніше виправимо",
    "zh-Hant": "稍後整理",
    "zh-Hans": "稍后整理",
  ]

  static func languageCode(_ code: String) -> String {
    let lower = code.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "_", with: "-").lowercased()
    if lower == "yue" || lower.hasPrefix("yue-") { return "zh-Hant" }
    if lower == "zh" || lower.hasPrefix("zh-") {
      return lower.contains("hans") || lower.contains("-cn") || lower.contains("-sg")
        ? "zh-Hans" : "zh-Hant"
    }
    let primary = String(lower.split(separator: "-").first ?? "en")
    return primary == "nb" || primary == "nn" ? "no" : primary
  }

  static func lines(outputCode: String?, interfaceCode: String)
    -> (listening: String, afterwards: String)
  {
    let code = outputCode.flatMap { $0.isEmpty ? nil : $0 } ?? interfaceCode
    let language = languageCode(code)
    return (
      listening[language] ?? listening["en"]!,
      afterwards[language] ?? afterwards["en"]!
    )
  }

  static func label(outputCode: String?, interfaceCode: String) -> String {
    let text = lines(outputCode: outputCode, interfaceCode: interfaceCode)
    return "\(text.listening) \(text.afterwards)"
  }

  static func supports(_ code: String) -> Bool {
    let key = languageCode(code)
    return listening[key] != nil && afterwards[key] != nil
  }
}
