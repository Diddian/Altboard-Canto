import Foundation
import Testing

@Suite("Offline multilingual Latin candidate safety")
struct LatinWordSuggestionPolicyTests {
  @Test func choosesOnlySelectedNonHanLanguages() {
    #expect(LatinWordSuggestionPolicy.preferredCodes(["yue", "de", "en", "de"]) == ["de", "en"])
    #expect(LatinWordSuggestionPolicy.preferredCodes(["zh", "yue"]) == [])
    #expect(LatinWordSuggestionPolicy.preferredCodes(["en-GB", "de-DE"]) == ["en", "de"])
  }

  @Test func resolvesInstalledLanguageIdentifiersInPreferenceOrder() {
    let locales = LatinWordSuggestionPolicy.checkerLocales(
      preferred: ["yue", "de", "en"],
      available: ["en_GB", "fr_FR", "de_DE"]
    )
    #expect(locales == [
      .init(preference: "de", identifier: "de_DE"),
      .init(preference: "en", identifier: "en_GB")
    ])
  }

  @Test func identifiesOnlyTheCurrentLatinWord() {
    #expect(LatinWordSuggestionPolicy.trailingWord(in: "Hallo sch") == "sch")
    #expect(LatinWordSuggestionPolicy.trailingWord(in: "Ich möchte Über") == "Über")
    #expect(LatinWordSuggestionPolicy.trailingWord(in: "今日 hello") == "hello")
    #expect(LatinWordSuggestionPolicy.trailingWord(in: "Hallo ") == nil)
    #expect(LatinWordSuggestionPolicy.trailingWord(in: "世界") == nil)
    #expect(LatinWordSuggestionPolicy.trailingWord(in: "a") == nil)
  }

  @Test func onlyReplacesVerifiedTextImmediatelyBeforeCursor() {
    #expect(LatinWordSuggestionPolicy.canReplace("gute", in: "Ich suche gute"))
    #expect(!LatinWordSuggestionPolicy.canReplace("gute", in: "Ich suche guten"))
    #expect(!LatinWordSuggestionPolicy.canReplace("gute", in: "Ich suche gute "))
  }

  @Test func offlinePrefixAndSingleEditSuggestionsAreBounded() {
    let words = ["recognition", "recording", "recovery", "typing", "calendar"]
    #expect(LatinWordSuggestionPolicy.fallbackCandidates(
      for: "reco", dictionary: words, limit: 3
    ) == ["recognition", "recording", "recovery"])
    #expect(LatinWordSuggestionPolicy.fallbackCandidates(
      for: "recognitjon", dictionary: words
    ) == ["recognition"])
    #expect(LatinWordSuggestionPolicy.fallbackCandidates(
      for: "calndar", dictionary: words
    ) == ["calendar"])
    #expect(LatinWordSuggestionPolicy.fallbackCandidates(
      for: "typing", dictionary: words
    ).isEmpty)
    #expect(LatinWordSuggestionPolicy.fallbackCandidates(
      for: "ab", dictionary: words
    ).isEmpty)
  }

  @Test func existingDictionaryWordsDoNotReceiveSpuriousFallbackCorrections() {
    let words = ["hello", "help", "hallo", "HalLo", "verfügbar"]
    #expect(LatinWordSuggestionPolicy.fallbackCandidates(
      for: "hello", dictionary: words
    ).isEmpty)
    #expect(LatinWordSuggestionPolicy.fallbackCandidates(
      for: "HALLO", dictionary: words
    ).isEmpty)
    #expect(LatinWordSuggestionPolicy.fallbackCandidates(
      for: "verfügbar", dictionary: words
    ).isEmpty)
    #expect(LatinWordSuggestionPolicy.fallbackCandidates(
      for: "verfugbar", dictionary: words
    ) == ["verfügbar"])
    #expect(LatinWordSuggestionPolicy.fallbackCandidates(
      for: "hello", dictionary: ["hello"], limit: 0
    ).isEmpty)
  }

  @Test func oneEditRecognizesTranspositionsWithoutBroadFalseMatches() {
    #expect(LatinWordSuggestionPolicy.oneEditApart("hallo", "halol"))
    #expect(LatinWordSuggestionPolicy.oneEditApart("schriben", "schreiben"))
    #expect(LatinWordSuggestionPolicy.oneEditApart("verfugbar", "verfügbar"))
    #expect(!LatinWordSuggestionPolicy.oneEditApart("world", "unrelated"))
    #expect(!LatinWordSuggestionPolicy.oneEditApart("recognition", "recognition"))
    #expect(!LatinWordSuggestionPolicy.oneEditApart("type", "type recognition"))
  }

  @Test func keepsInputCapitalization() {
    #expect(LatinWordSuggestionPolicy.matchCapitalization("hello", typed: "Hel") == "Hello")
    #expect(LatinWordSuggestionPolicy.matchCapitalization("hello", typed: "HEL") == "HELLO")
    #expect(LatinWordSuggestionPolicy.matchCapitalization("hallo", typed: "hal") == "hallo")
  }
}
