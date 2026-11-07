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
      let lines = LiveDictationNotice.lines(outputCode: code, interfaceCode: "en")
      precondition(!lines.listening.isEmpty && lines.listening.hasSuffix("…"))
      precondition(!lines.afterwards.isEmpty)
      precondition(LiveDictationNotice.label(outputCode: code, interfaceCode: "en")
        == "\(lines.listening) \(lines.afterwards)")
    }
    precondition(LiveDictationNotice.label(outputCode: "en", interfaceCode: "de")
      == "Listening… tidy afterwards")
    precondition(LiveDictationNotice.label(outputCode: "yue-HK", interfaceCode: "en")
      == "聆聽中… 稍後整理")
    precondition(LiveDictationNotice.label(outputCode: "", interfaceCode: "zh-HK")
      == "聆聽中… 稍後整理")
    precondition(LiveDictationNotice.label(outputCode: "de-DE", interfaceCode: "en")
      .contains("danach"))
    precondition(LiveDictationNotice.label(outputCode: "fr", interfaceCode: "de")
      .contains("ensuite"))
    precondition(LiveDictationNotice.label(outputCode: "xyz", interfaceCode: "de")
      == "Listening… tidy afterwards")
    print("Listening notice localization passed for \(supported.count) languages")
  }
}
