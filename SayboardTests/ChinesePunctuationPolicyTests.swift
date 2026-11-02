import Foundation
import Testing

@Suite("Traditional Chinese punctuation")
struct ChinesePunctuationPolicyTests {
  @Test func openingClosingAndParagraphReset() {
    #expect(ChinesePunctuationPolicy.nextCornerQuote(after: "") == "「")
    #expect(ChinesePunctuationPolicy.nextCornerQuote(after: "佢話「") == "」")
    #expect(ChinesePunctuationPolicy.nextCornerQuote(after: "佢話「你好」") == "「")
    #expect(ChinesePunctuationPolicy.nextCornerQuote(after: "「你好」\n") == "「")
  }

  @Test func manualInnerQuotesDoNotBreakOuterQuote() {
    #expect(ChinesePunctuationPolicy.nextCornerQuote(after: "佢話「『係呀』") == "」")
    #expect(ChinesePunctuationPolicy.nextCornerQuote(after: "佢話『係呀』") == "「")
    #expect(ChinesePunctuationPolicy.nextCornerQuote(after: "「再「內」") == "」")
  }

  @Test func unmatchedClosingQuoteDoesNotCauseNegativeDepth() {
    #expect(ChinesePunctuationPolicy.nextCornerQuote(after: "」") == "「")
    #expect(ChinesePunctuationPolicy.nextCornerQuote(after: "」「") == "」")
  }
}
