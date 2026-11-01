import Foundation
import Testing

@Suite("Sentence capitalization")
struct SentenceCapitalizationTests {
  @Test func startsUppercase() {
    #expect(SentenceCapitalization.shouldUseUppercase(after: nil))
    #expect(SentenceCapitalization.shouldUseUppercase(after: ""))
    #expect(SentenceCapitalization.shouldUseUppercase(after: "  "))
  }

  @Test func keepsLowercaseInsideASentence() {
    #expect(!SentenceCapitalization.shouldUseUppercase(after: "A"))
    #expect(!SentenceCapitalization.shouldUseUppercase(after: "Hello "))
    #expect(!SentenceCapitalization.shouldUseUppercase(after: "www.example"))
  }

  @Test func capitalizesAfterPunctuation() {
    for text in ["Hello.", "Hello. ", "Really!  ", "What? ", "你好。", "你好！ ", "你係邊位？"] {
      #expect(SentenceCapitalization.shouldUseUppercase(after: text))
    }
  }

  @Test func capitalizesAfterNewline() {
    #expect(SentenceCapitalization.shouldUseUppercase(after: "Hello\n"))
    #expect(SentenceCapitalization.shouldUseUppercase(after: "Hello\n  "))
    #expect(SentenceCapitalization.shouldUseUppercase(after: "Hello\r\n"))
    #expect(!SentenceCapitalization.shouldUseUppercase(after: "Hello\nWorld"))
  }
}
