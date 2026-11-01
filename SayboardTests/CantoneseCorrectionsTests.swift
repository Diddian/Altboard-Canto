import Foundation
import Testing

@Suite("Cantonese speech corrections")
struct CantoneseCorrectionsTests {
  @Test func builtinInterjection() {
    #expect(CantoneseCorrections.apply("餵，你做乜嘢呀？", customRules: []) == "喂，你做乜嘢呀？")
    #expect(CantoneseCorrections.apply("餵你點呀？", customRules: []) == "喂你點呀？")
  }

  @Test func feedingWordsStayIntact() {
    for phrase in ["餵食咗未？", "我餵隻貓食嘢", "餵奶", "餵你食飯啦"] {
      #expect(CantoneseCorrections.apply(phrase, customRules: []) == phrase)
    }
  }

  @Test func customRuleWorksWithoutCleanup() {
    let rule = CantoneseCorrectionRule(heard: "餵，你", intended: "喂，你")
    #expect(CantoneseCorrections.apply("佢講餵你", customRules: [rule]) == "佢講喂，你")
    #expect(CantoneseCorrections.apply("佢講餵，你", customRules: [rule]) == "佢講喂，你")
    #expect(CantoneseCorrections.apply("佢講餵 你", customRules: [rule]) == "佢講喂，你")
    #expect(CantoneseCorrections.applyDetailed("餵你", customRules: [rule]).matchedRules == 1)
  }

  @Test func personalCorrectionWinsOverBuiltin() {
    let rule = CantoneseCorrectionRule(heard: "餵你", intended: "喂，你")
    #expect(CantoneseCorrections.apply("餵你做乜嘢呀？", customRules: [rule]) == "喂，你做乜嘢呀？")
  }

  @Test func unrelatedWordsAreNotChanged() {
    let rule = CantoneseCorrectionRule(heard: "餵，你", intended: "喂，你")
    #expect(CantoneseCorrections.apply("餵食", customRules: [rule]) == "餵食")
    #expect(CantoneseCorrections.apply("餵奶", customRules: [rule]) == "餵奶")
  }

  @Test func invalidSingleCharacterRuleIgnored() {
    let rule = CantoneseCorrectionRule(heard: "餵", intended: "喂")
    #expect(CantoneseCorrections.apply("餵食", customRules: [rule]) == "餵食")
  }
}


/// This mirrors the Chinese transform in the app without linking the main
/// application module into the Shared-only unit-test target.
private func testChineseNormalization(_ text: String) -> String {
  text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
}

@Suite("Cantonese final output after Traditional Chinese conversion")
struct CantoneseFinalizationTests {
  @Test func greetingRestoredAfterHansHant() {
    let original = "喂，你做乜嘢呀？"
    let converted = testChineseNormalization(original)
    // The unqualified Hans-Hant transform can undo a proper HK greeting.
    #expect(CantoneseCorrections.apply(converted, customRules: []) == original)
  }

  @Test func savedRuleAppliedAfterConversion() {
    let wrong = "餵，你做乜嘢呀？"
    let correction = CantoneseCorrectionRule(heard: "餵，你", intended: "喂，你")
    let converted = testChineseNormalization(wrong)
    let result = CantoneseCorrections.applyDetailed(converted, customRules: [correction])
    #expect(result.text == "喂，你做乜嘢呀？")
    #expect(result.matchedRules == 1)
  }

  @Test func feedingWordsNotReplaced() {
    let input = "我餵你食飯啦"
    #expect(CantoneseCorrections.apply(testChineseNormalization(input), customRules: []) == input)
  }
}
