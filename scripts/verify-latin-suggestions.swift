import Foundation

@main
struct VerifyLatinSuggestions {
  static func main() {
    let choices = LatinWordSuggestionPolicy.checkerLocales(
      preferred: ["yue", "en", "de", "en"],
      available: ["de_DE", "fr_FR", "en_GB"]
    )
    precondition(choices.map(\.preference) == ["en", "de"])
    precondition(choices.map(\.identifier) == ["en_GB", "de_DE"])
    precondition(LatinWordSuggestionPolicy.trailingWord(in: "Hello schöne") == "schöne")
    precondition(LatinWordSuggestionPolicy.trailingWord(in: "Hallo ") == nil)
    precondition(LatinWordSuggestionPolicy.trailingWord(in: "中文字") == nil)
    precondition(LatinWordSuggestionPolicy.canReplace("Hallo", in: "ja Hallo"))
    precondition(!LatinWordSuggestionPolicy.canReplace("Hallo", in: "ja Hallo "))
    precondition(LatinWordSuggestionPolicy.matchCapitalization("hello", typed: "HEL") == "HELLO")
    let fallback = LatinWordSuggestionPolicy.fallbackCandidates(
      for: "recognitjon", dictionary: ["recognition", "recording", "typing"]
    )
    precondition(fallback == ["recognition"])
    precondition(LatinWordSuggestionPolicy.oneEditApart("halol", "hallo"))
    precondition(LatinWordSuggestionPolicy.oneEditApart("schriben", "schreiben"))
    precondition(!LatinWordSuggestionPolicy.oneEditApart("hello", "recognition"))
    precondition(LatinWordSuggestionPolicy.fallbackCandidates(
      for: "hello", dictionary: ["hello", "help"]
    ).isEmpty)
    precondition(LatinWordSuggestionPolicy.fallbackCandidates(
      for: "verfugbar", dictionary: ["verfügbar", "Vertrag"]
    ) == ["verfügbar"])
    precondition(LatinWordSuggestionPolicy.fallbackCandidates(
      for: "reco", dictionary: ["recognition", "recording", "recovery"]
    ).count == 3)
    print("Multilingual Latin suggestion safety verified")
  }
}
