import Foundation

@main
enum VerifyLanguagePriority {
  static func main() {
    precondition(LanguagePriority.ordered(["zh", "yue", "en", "de"]) == ["zh", "yue", "en", "de"])
    precondition(LanguagePriority.ordered(["de-DE", "ja-JP", "en_US", "de"]) == ["de", "ja", "en"])
    precondition(LanguagePriority.ordered(["cmn-Hant", "yue-HK"]) == ["zh", "yue"])
    precondition(LanguagePriority.ordered(["de", "ja", "en"], available: ["en", "de"]) == ["de", "en"])
    let languages = ["de", "ja", "en"]
    precondition(LanguagePriority.moving(languages, offsets: [1], to: 0) == ["ja", "de", "en"])
    precondition(LanguagePriority.moving(languages, offsets: [0], to: 3) == ["ja", "en", "de"])
    precondition(LanguagePriority.moving(languages, offsets: [0, 2], to: 3) == ["ja", "de", "en"])
    precondition(LanguagePriority.moving(languages, offsets: [99], to: 0) == languages)
    precondition(LanguagePriority.boost(for: "de", preferred: languages)
      > LanguagePriority.boost(for: "en", preferred: languages))
    precondition(LanguagePriority.boost(for: "fr", preferred: languages) == 0)
    // Strong local context can outweigh the stored language order.
    precondition(18 + LanguagePriority.boost(for: "en", preferred: languages)
      > LanguagePriority.boost(for: "de", preferred: languages))
    print("Ordered language selection, reordering and bounded ranking passed")
  }
}
