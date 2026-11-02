import Foundation
import Testing

@Suite("Live Cantonese suffix safety")
struct LiveCantoneseSafetyTests {
  @Test func onlyCurrentSuffixCanBeReplaced() {
    #expect(LiveCantoneseSafety.matches(buffer: "gamyat", hostContext: "Some Gamyat"))
    #expect(!LiveCantoneseSafety.matches(buffer: "gamyat", hostContext: "gamy"))
    #expect(!LiveCantoneseSafety.matches(buffer: "gamyat", hostContext: nil))
    #expect(!LiveCantoneseSafety.matches(buffer: "gamyat", hostContext: "gamyat plus"))
  }

  @Test func EnglishNeverDeletedAsRomanizationWithoutCandidates() {
    #expect(!LiveCantoneseSafety.canDeleteAsToken(
      buffer: "hello", candidateCount: 0, hostContext: "hello"))
    #expect(LiveCantoneseSafety.canDeleteAsToken(
      buffer: "gamyat", candidateCount: 2, hostContext: "I typed gamyat"))
  }
}
