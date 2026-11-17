import Foundation

enum TutorialVideo: String {
  case microphone = "tutorial-microphone"
  case addKeyboard = "tutorial-add-keyboard"
  case fullAccess = "tutorial-full-access"

  static func resourceLanguages(for language: String) -> [String] {
    let chosen = AppLanguageConfig.supported.contains(language) ? language : AppLanguageConfig.fallback
    switch chosen {
    case "zh-Hans", "zh-Hant":
      // Chinese tutorials ship as a shared -zh asset until script-specific media exists.
      return [chosen, "zh", AppLanguageConfig.fallback]
    default:
      return chosen == AppLanguageConfig.fallback ? [chosen] : [chosen, AppLanguageConfig.fallback]
    }
  }

  func url(for language: String) -> URL? {
    for code in Self.resourceLanguages(for: language) {
      if let url = Bundle.main.url(forResource: "\(self.rawValue)-\(code)", withExtension: "mp4") {
        return url
      }
    }
    return nil
  }
}
