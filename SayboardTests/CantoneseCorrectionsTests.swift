import Testing

@Suite("Cantonese speech corrections")
struct CantoneseCorrectionsTests {
  @Test func greetingAtStart() {
    #expect(CantoneseCorrections.apply("餵，你做乜嘢呀？", customRules: []) == "喂，你做乜嘢呀？")
    #expect(CantoneseCorrections.apply("餵你點呀？", customRules: []) == "喂你點呀？")
    #expect(CantoneseCorrections.apply("喂，你做乜嘢呀？", customRules: []) == "喂，你做乜嘢呀？")
  }

  @Test func feedingWordsRemainIntact() {
    #expect(CantoneseCorrections.apply("餵食咗未？", customRules: []) == "餵食咗未？")
    #expect(CantoneseCorrections.apply("我餵隻貓食嘢", customRules: []) == "我餵隻貓食嘢")
    #expect(CantoneseCorrections.apply("餵奶", customRules: []) == "餵奶")
    #expect(CantoneseCorrections.apply("餵你食飯啦", customRules: []) == "餵你食飯啦")
  }

  @Test func explicitPhraseLearning() {
    let rule = CantoneseCorrectionRule(heard: "餵，你", intended: "喂，你")
    #expect(CantoneseCorrections.apply("佢講餵，你", customRules: [rule]) == "佢講喂，你")
  }

  @Test func invalidOverbroadRulesAreIgnored() {
    let rule = CantoneseCorrectionRule(heard: "餵", intended: "喂")
    #expect(CantoneseCorrections.apply("餵食", customRules: [rule]) == "餵食")
  }
}
