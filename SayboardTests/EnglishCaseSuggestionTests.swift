import Foundation
import Testing

@Suite("English suggestions alongside Cantonese")
struct EnglishCaseSuggestionTests {
  @Test func suggestsUppercaseOK() {
    #expect(EnglishCaseSuggestion.replacement(for: "ok") == "OK")
    #expect(EnglishCaseSuggestion.replacement(for: "Ok") == "OK")
    #expect(EnglishCaseSuggestion.replacement(for: "OK") == nil)
  }
  @Test func doesNotHijackOtherEnglish() {
    #expect(EnglishCaseSuggestion.replacement(for: "okay") == nil)
    #expect(EnglishCaseSuggestion.replacement(for: "book") == nil)
    #expect(EnglishCaseSuggestion.replacement(for: "gamyat") == nil)
  }
}
