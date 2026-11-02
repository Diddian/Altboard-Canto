import Foundation
import Testing

@Suite("Cantonese phonetic syllable deletion")
struct CantoneseSyllableEditingTests {
  @Test func deletesFinalYaleSyllableNotWholePhrase() {
    #expect(CantoneseSyllableEditing.lastSyllableLength(
      typed: "Gamyat", canonical: "gam1 jat6") == 3)
    #expect(CantoneseSyllableEditing.lastSyllableLength(
      typed: "gamjat", canonical: "gam1 jat6") == 3)
  }

  @Test func supportsToneDigitsAndSingleSyllable() {
    #expect(CantoneseSyllableEditing.lastSyllableLength(
      typed: "gam1jat6", canonical: "gam1 jat6") == 4)
    #expect(CantoneseSyllableEditing.lastSyllableLength(
      typed: "yat", canonical: "jat6") == 3)
  }

  @Test func yaleOnsetAndSidneyFinalsDoNotLoseLetters() {
    #expect(CantoneseSyllableEditing.yaleAlias("jyu5") == "yu")
    #expect(CantoneseSyllableEditing.yaleAlias("jyun4") == "yun")
    #expect(CantoneseSyllableEditing.yaleAlias("jyut6") == "yut")
    #expect(CantoneseSyllableEditing.sidneyLauAlias("zoeng1") == "jeung")
    #expect(CantoneseSyllableEditing.sidneyLauAlias("goeng1") == "geung")
  }

  @Test func supportsSidneyLauSyllableDeletion() {
    #expect(CantoneseSyllableEditing.lastSyllableLength(
      typed: "gamyuen", canonical: "gam1 jyun4") == 4)
    #expect(CantoneseSyllableEditing.lastSyllableLength(
      typed: "seui", canonical: "seoi2") == 4)
    #expect(CantoneseSyllableEditing.lastSyllableLength(
      typed: "sui", canonical: "seoi2") == 3)
    #expect(CantoneseSyllableEditing.lastSyllableLength(
      typed: "jui", canonical: "zeoi3") == 3)
  }

  @Test func invalidOrEnglishSpellingFallsBackToOneCharacter() {
    #expect(CantoneseSyllableEditing.lastSyllableLength(
      typed: "gamyzt", canonical: "gam1 jat6") == nil)
    #expect(CantoneseSyllableEditing.lastSyllableLength(
      typed: "hello", canonical: "gam1 jat6") == nil)
  }
}
