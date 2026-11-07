import Foundation

/// Recording-stage copy: the displayed live transcript is provisional.
/// This never changes the transcript or the selected translation target.
enum LiveDictationNotice {
  private static let afterRecording: [String: String] = [
    "en": "tidied after recording",
    "bg": "ще се редактира след записа",
    "cs": "upraví se po nahrávání",
    "da": "bearbejdes efter optagelse",
    "de": "wird nach Aufnahme überarbeitet",
    "el": "θα διορθωθεί μετά την εγγραφή",
    "es": "se revisará tras grabar",
    "et": "korrigeeritakse pärast salvestust",
    "fi": "siistitään tallennuksen jälkeen",
    "fr": "sera revu après l’enregistrement",
    "hi": "रिकॉर्डिंग के बाद सुधारा जाएगा",
    "hr": "uredit će se nakon snimanja",
    "hu": "felvétel után javítjuk",
    "it": "verrà sistemato dopo la registrazione",
    "ja": "録音後に整えます",
    "ko": "녹음 후 다듬어요",
    "lt": "po įrašymo bus pataisyta",
    "lv": "pēc ieraksta tiks labots",
    "nl": "wordt na opname bijgewerkt",
    "no": "bearbeides etter opptak",
    "pl": "zostanie poprawiony po nagraniu",
    "pt": "será revisto após a gravação",
    "ro": "va fi revizuit după înregistrare",
    "ru": "после записи текст будет исправлен",
    "sk": "upraví sa po nahrávaní",
    "sl": "urejeno po snemanju",
    "sv": "bearbetas efter inspelning",
    "tr": "kayıttan sonra düzenlenecek",
    "uk": "буде виправлено після запису",
    "zh-Hant": "錄後會整理",
    "zh-Hans": "录后会整理",
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

  /// AUTO uses the keyboard's interface language. An explicit output target
  /// selects its own language, including supported custom output languages.
  static func label(outputCode: String?, interfaceCode: String) -> String {
    let code = outputCode.flatMap { $0.isEmpty ? nil : $0 } ?? interfaceCode
    let language = languageCode(code)
    let note = afterRecording[language] ?? afterRecording["en"]!
    if language == "zh-Hant" || language == "zh-Hans" {
      return "Live Dictation（\(note)）"
    }
    return "Live Dictation (\(note))"
  }

  static func supports(_ code: String) -> Bool {
    afterRecording[languageCode(code)] != nil
  }
}
