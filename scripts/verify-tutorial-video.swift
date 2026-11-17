import Foundation

// Minimal fixture for the app's language contract; this verifier only checks
// deterministic language lookup, not native Bundle resource loading.
enum AppLanguageConfig {
  static let fallback = "en"
  static let supported: Set<String> = ["en", "de", "zh-Hans", "zh-Hant"]
}

@main
enum VerifyTutorialVideo {
  static func main() {
    precondition(TutorialVideo.resourceLanguages(for: "zh-Hant") == ["zh-Hant", "zh", "en"])
    precondition(TutorialVideo.resourceLanguages(for: "zh-Hans") == ["zh-Hans", "zh", "en"])
    precondition(TutorialVideo.resourceLanguages(for: "de") == ["de", "en"])
    precondition(TutorialVideo.resourceLanguages(for: "en") == ["en"])
    precondition(TutorialVideo.resourceLanguages(for: "xx") == ["en"])
    print("Tutorial video locale resolution passed")
  }
}
