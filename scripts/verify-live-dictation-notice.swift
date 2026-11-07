import Foundation

@main
enum VerifyLiveDictationNotice {
  static func main() {
    let supported = [
      "en", "bg", "cs", "da", "de", "el", "es", "et", "fi", "fr", "hi", "hr",
      "hu", "it", "ja", "ko", "lt", "lv", "nl", "no", "pl", "pt", "ro", "ru",
      "sk", "sl", "sv", "tr", "uk", "zh-Hans", "zh-Hant"
    ]
    for code in supported {
      precondition(LiveDictationNotice.supports(code), "Missing localized language \(code)")
      let label = LiveDictationNotice.label(outputCode: code, interfaceCode: "en")
      precondition(label.hasPrefix("Live Dictation"))
      precondition(label.contains("(") || label.contains("（"))
    }
    precondition(LiveDictationNotice.label(outputCode: "yue-HK", interfaceCode: "en")
      == "Live Dictation（錄後會整理）")
    precondition(LiveDictationNotice.label(outputCode: "", interfaceCode: "zh-HK")
      == "Live Dictation（錄後會整理）")
    precondition(LiveDictationNotice.label(outputCode: "de-DE", interfaceCode: "en")
      .contains("nach Aufnahme"))
    precondition(LiveDictationNotice.label(outputCode: "fr", interfaceCode: "de")
      .contains("enregistrement"))
    precondition(LiveDictationNotice.label(outputCode: "xyz", interfaceCode: "de")
      .contains("tidied after recording"))
    print("Live dictation hint localization passed for \(supported.count) interface languages")
  }
}
