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
    precondition(LatinWordSuggestionPolicy.swipeLeadingSeparator(in: "I") == " ")
    precondition(LatinWordSuggestionPolicy.swipeLeadingSeparator(in: "I think ") == "")
    precondition(LatinWordSuggestionPolicy.swipeLeadingSeparator(in: "Hallo!") == "")
    precondition(LatinWordSuggestionPolicy.swipeLeadingSeparator(in: "你好") == "")
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
    let split = LatinWordSuggestionPolicy.splitPhraseCorrections(
      for: "somepeolpe", dictionary: ["some", "people", "someone", "other"]
    )
    precondition(split.contains("some people"),
                 "explicit split phrase correction should be offered: \(split)")
    precondition(LatinWordSuggestionPolicy.uniqueCorrection(["Berlin"], typed: "berln") == "Berlin")
    precondition(LatinWordSuggestionPolicy.uniqueCorrection(["form", "from"], typed: "frmo") == nil)
    precondition(LatinWordSuggestionPolicy.uniqueCorrection(["morgen", "Morgen"], typed: "morgn") == nil)
    precondition(LatinWordSuggestionPolicy.uniqueCorrection([], typed: "morgn") == nil)
    let words = ["good", "morning", "in", "Berlin", "Morgen", "gut", "house", "household"]
    precondition(LatinWordSuggestionPolicy.splitPhraseCorrections(
      for: "goodmorning", dictionary: words, limit: 1
    ) == ["good morning"])
    precondition(LatinWordSuggestionPolicy.splitPhraseCorrections(
      for: "inberlin", dictionary: words, limit: 1
    ) == ["in Berlin"])
    precondition(LatinWordSuggestionPolicy.splitPhraseCorrections(
      for: "Berlinin", dictionary: words, limit: 1
    ) == ["Berlin in"])
    precondition(LatinWordSuggestionPolicy.splitPhraseCorrections(
      for: "household", dictionary: words + ["hold"]
    ).isEmpty)
    print("Multilingual Latin suggestion safety verified")
  }
}
