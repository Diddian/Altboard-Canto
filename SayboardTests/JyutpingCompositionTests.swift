import Foundation
import Testing

@Suite("Jyutping composition buffer")
struct JyutpingCompositionTests {
  @Test func acceptsJyutpingAndToneDigits() {
    var composition = JyutpingComposition()
    for value in ["N","e","i","5","h","o","u","2"] {
      #expect(composition.append(value))
    }
    #expect(composition.buffer == "nei5hou2")
  }

  @Test func backspaceNeverDeletesHostTextInsideComposition() {
    var composition = JyutpingComposition()
    #expect(!composition.backspace())
    #expect(composition.append("n"))
    #expect(composition.backspace())
    #expect(composition.isEmpty)
    #expect(!composition.backspace())
  }

  @Test func syllableDeletionPreservesEarlierLatinComposition() {
    var composition = JyutpingComposition()
    for key in "gamyat" { #expect(composition.append(String(key))) }
    composition.removeLast(3)
    #expect(composition.buffer == "gam")
  }

  @Test func cantonesePhraseCandidateAndSpaceSelection() {
    #expect(CantonesePhraseCommitPolicy.hidesLatinLiteral(
      firstCandidate: "幾快", isCurrentComposition: true, hasExactEntry: true
    ))
    #expect(!CantonesePhraseCommitPolicy.hidesLatinLiteral(
      firstCandidate: "幾快", isCurrentComposition: false, hasExactEntry: true
    ))
    #expect(!CantonesePhraseCommitPolicy.hidesLatinLiteral(
      firstCandidate: "幾", isCurrentComposition: true, hasExactEntry: true
    ))
    #expect(!CantonesePhraseCommitPolicy.hidesLatinLiteral(
      firstCandidate: "幾快", isCurrentComposition: true, hasExactEntry: false
    ))
    #expect(CantonesePhraseCommitPolicy.commitsFirstOnSpace(
      spelling: "gifai", firstCandidate: "幾快", hasExactEntry: true, hostMatches: true
    ))
    #expect(!CantonesePhraseCommitPolicy.commitsFirstOnSpace(
      spelling: "gifai", firstCandidate: "幾快", hasExactEntry: false, hostMatches: true
    ))
    #expect(!CantonesePhraseCommitPolicy.commitsFirstOnSpace(
      spelling: "gifai", firstCandidate: "幾快", hasExactEntry: true, hostMatches: false
    ))
    #expect(!CantonesePhraseCommitPolicy.commitsFirstOnSpace(
      spelling: "hello", firstCandidate: nil, hasExactEntry: false, hostMatches: true
    ))
    #expect(!CantonesePhraseCommitPolicy.hidesLatinLiteral(
      firstCandidate: "好咩", isCurrentComposition: true, hasExactEntry: true, recognizesLatinWord: true
    ))
    #expect(!CantonesePhraseCommitPolicy.commitsFirstOnSpace(
      spelling: "home", firstCandidate: "好咩", hasExactEntry: true,
      hostMatches: true, recognizesLatinWord: true
    ))
    #expect(CantoneseRomanizationVariants.variants(for: "gifai").contains("geifaai"))
  }

  @Test func rejectsInvalidKeysWithoutChangingBuffer() {
    var composition = JyutpingComposition()
    #expect(composition.append("n"))
    #expect(!composition.append("."))
    #expect(!composition.append("7"))
    #expect(!composition.append("é"))
    #expect(composition.buffer == "n")
    composition.clear()
    #expect(composition.isEmpty)
  }
}
