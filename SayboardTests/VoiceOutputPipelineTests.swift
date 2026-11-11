import Foundation
import Testing

@Suite("Offline voice output")
struct VoiceOutputPipelineTests {
  @Test
  func defaultsPreserveOriginalLanguageAndTone() {
    let options = VoiceOutputConfiguration(
      cleanupEnabled: true, target: .original, register: .faithful, customLanguage: ""
    )
    let prompt = VoiceOutputPrompt.systemPrompt(for: options)
    #expect(options.needsLLM)
    #expect(prompt.contains("Do not translate"))
    #expect(prompt.contains("Cantonese"))
    #expect(prompt.contains("code-switching"))
    #expect(prompt.contains("Do not invent"))
  }

  @Test
  func germanFormalOutputKeepsMeaning() {
    let options = VoiceOutputConfiguration(
      cleanupEnabled: true, target: .german, register: .formal, customLanguage: ""
    )
    let prompt = VoiceOutputPrompt.systemPrompt(for: options)
    #expect(prompt.contains("German"))
    #expect(prompt.contains("professional"))
    #expect(prompt.contains("negation"))
    #expect(prompt.contains("translate the Cantonese content as well"))
  }

  @Test
  func noCleanupWithOriginalLanguageSkipsLLM() {
    let options = VoiceOutputConfiguration(
      cleanupEnabled: false, target: .original, register: .faithful, customLanguage: ""
    )
    #expect(!options.needsLLM)
  }

  @Test
  func translationRunsWithoutCleanup() {
    let options = VoiceOutputConfiguration(
      cleanupEnabled: false, target: .english, register: .casual, customLanguage: ""
    )
    #expect(options.needsLLM)
  }

  @Test
  func explicitLanguageRejectsUntranslatedCantonese() {
    #expect(!VoiceLanguageValidator.matches("我唔想同你講嘢", target: .german))
    #expect(!VoiceLanguageValidator.matches("我唔想同你講嘢", target: .english))
    #expect(VoiceLanguageValidator.matches("Ich bin müde.", target: .german))
    #expect(VoiceLanguageValidator.matches("I am tired.", target: .english))
    #expect(!VoiceLanguageValidator.matches("English only", target: .cantonese))
  }

  @Test
  func compactOfflineTranslationRetainsTargetAndIntegrity() {
    let options = VoiceOutputConfiguration(
      cleanupEnabled: false, target: .cantonese,
      register: .faithful, customLanguage: ""
    )
    let prompt = VoiceOutputPrompt.compactPrompt(for: options)
    #expect(prompt.contains("Hong Kong"))
    #expect(prompt.contains("Traditional Chinese"))
    #expect(prompt.contains("Preserve every fact"))
    #expect(prompt.contains("UNTRUSTED ASR transcript"))
    #expect(prompt.count < VoiceOutputPrompt.systemPrompt(for: options).count)
  }

  @Test
  func cantoneseValidationRejectsUntranslatedShortLatin() {
    #expect(!VoiceLanguageValidator.matches("Merhaba", target: .cantonese))
    #expect(!VoiceLanguageValidator.matches("Hello", target: .traditionalChinese))
    #expect(VoiceLanguageValidator.matches("你而家喺邊度？", target: .cantonese))
    #expect(VoiceLanguageValidator.matches("123", target: .cantonese))
  }

  @Test
  func rejectsJapaneseAndUntranslatedGermanIntro() {
    #expect(!VoiceLanguageValidator.matches("シド、上だ。それはなんの冗談？", target: .cantonese))
    #expect(!VoiceLanguageValidator.matches("Ja, 我暫可以哋理解。", target: .cantonese))
    #expect(!VoiceLanguageValidator.matches("안녕하세요我", target: .traditionalChinese))
    #expect(VoiceLanguageValidator.matches("係，我聽得明。", target: .cantonese))
    #expect(VoiceLanguageValidator.matches("我用 iPhone 17 Pro Max。", target: .cantonese))
    #expect(VoiceOutputPrompt.maximumTranslationAttempts == 2)
  }

  @Test
  func keyboardCyclesOutputLanguages() {
    #expect(VoiceOutputTarget.nextKeyboardTarget(after: .original) == .cantonese)
    #expect(VoiceOutputTarget.nextKeyboardTarget(after: .cantonese) == .english)
    #expect(VoiceOutputTarget.nextKeyboardTarget(after: .english) == .german)
    #expect(VoiceOutputTarget.nextKeyboardTarget(after: .german) == .original)
  }

  @Test
  func outputLanguageChangesAfterMicOrDuringProcessing() {
    let original = VoiceOutputConfiguration(
      cleanupEnabled: false, target: .original, register: .faithful, customLanguage: ""
    )
    let german = VoiceOutputConfiguration(
      cleanupEnabled: false, target: .german, register: .faithful, customLanguage: ""
    )
    let english = VoiceOutputConfiguration(
      cleanupEnabled: false, target: .english, register: .faithful, customLanguage: ""
    )
    #expect(VoiceOutputSelectionPolicy.decide(
      processed: original, current: german, attempt: 1) == .retry)
    #expect(VoiceOutputSelectionPolicy.decide(
      processed: german, current: original, attempt: 1) == .retry)
    #expect(VoiceOutputSelectionPolicy.decide(
      processed: german, current: english, attempt: 2) == .retry)
    #expect(VoiceOutputSelectionPolicy.decide(
      processed: english, current: english, attempt: 3) == .deliver)
    #expect(VoiceOutputSelectionPolicy.decide(
      processed: german, current: english, attempt: 3) == .reject)
  }

  @Test
  func outputLanguageAbbreviationsMatchKeyboard() {
    #expect(VoiceOutputTarget.original.abbreviatedLabel(customLanguage: "") == "AUTO")
    #expect(VoiceOutputTarget.english.abbreviatedLabel(customLanguage: "") == "EN")
    #expect(VoiceOutputTarget.german.abbreviatedLabel(customLanguage: "") == "DE")
    #expect(VoiceOutputTarget.cantonese.abbreviatedLabel(customLanguage: "") == "粵")
    #expect(VoiceOutputTarget.custom.abbreviatedLabel(customLanguage: "fr") == "FR")
    #expect(VoiceOutputTarget.custom.abbreviatedLabel(customLanguage: "zh-Hans") == "简")
  }

  @Test
  func finalPunctuationDoesNotChangeIntermediateSpeech() {
    let raw = "喂，你好！I am here."
    #expect(VoicePunctuationPolicy.render(raw, enabled: true) == raw)
    #expect(VoicePunctuationPolicy.render(raw, enabled: false) == "喂 你好 I am here")
  }

  @Test
  func simplifiedChineseSelectionDoesNotBecomeTraditionalOnDelivery() {
    let simplified = VoiceOutputConfiguration(
      cleanupEnabled: true, target: .custom, register: .faithful,
      customLanguage: "zh-Hans"
    )
    let cantonese = VoiceOutputConfiguration(
      cleanupEnabled: false, target: .cantonese, register: .faithful,
      customLanguage: ""
    )
    #expect(simplified.isSimplifiedChinese)
    #expect(!cantonese.isSimplifiedChinese)
    #expect(VoiceOutputPrompt.systemPrompt(for: simplified).contains("Simplified Chinese"))
    #expect(VoiceOutputScriptPolicy.simplify("廁所") == "厕所")
    #expect(!cantonese.isSimplifiedChinese)
  }

  @Test
  func languageLabelsUseNativeScriptsWithoutChangingLanguageCodes() {
    #expect(PreferredVoiceLanguages.shortLabel(for: "yue") == "粵")
    #expect(PreferredVoiceLanguages.shortLabel(for: "zh") == "普")
    #expect(PreferredVoiceLanguages.shortLabel(for: "ja") == "日")
    #expect(PreferredVoiceLanguages.shortLabel(for: "ar") == "عر")
    #expect(PreferredVoiceLanguages.shortLabel(for: "fr") == "FR")
    #expect(PreferredVoiceLanguages.outputShortLabel(for: "zh") == "繁")
    #expect(PreferredVoiceLanguages.outputShortLabel(for: "zh-Hans") == "简")
    #expect(PreferredVoiceLanguages.outputShortLabel(for: "yue") == "粵")
    #expect(PreferredVoiceLanguages.currentCode(
      target: .custom, custom: "ja") == "ja")
  }

  @Test
  func originalSpeechRetainsWritingSystemUntilExplicitOutputConversion() {
    let original = VoiceOutputConfiguration(
      cleanupEnabled: false, target: .original,
      register: .faithful, customLanguage: ""
    )
    let cantonese = VoiceOutputConfiguration(
      cleanupEnabled: false, target: .cantonese,
      register: .faithful, customLanguage: ""
    )
    let simplified = VoiceOutputConfiguration(
      cleanupEnabled: false, target: .custom,
      register: .faithful, customLanguage: "zh-Hans"
    )
    let german = VoiceOutputConfiguration(
      cleanupEnabled: false, target: .german,
      register: .faithful, customLanguage: ""
    )
    #expect(CantoneseOutput.normalizeForOutput("厕所", options: original) == "厕所")
    #expect(CantoneseOutput.normalizeForOutput("厕所", options: cantonese) == "廁所")
    #expect(CantoneseOutput.normalizeForOutput("廁所", options: simplified) == "厕所")
    #expect(CantoneseOutput.normalizeForOutput("德国", options: german) == "德国")
    #expect(CantoneseOutput.normalizeForOutput("日本語", options: original) == "日本語")
  }

  @Test
  func restoresCantoneseFirstLiveAndFinalScriptWithoutChangingOtherTargets() {
    let original = VoiceOutputConfiguration(
      cleanupEnabled: false, target: .original, register: .faithful, customLanguage: ""
    )
    let simplified = VoiceOutputConfiguration(
      cleanupEnabled: false, target: .custom, register: .faithful, customLanguage: "zh-Hans"
    )
    #expect(CantoneseOutput.normalizeDictation("厕所", options: original,
      preferredLanguages: ["yue", "en", "de"]) == "廁所")
    #expect(CantoneseOutput.normalizeDictation("厕所", options: original,
      preferredLanguages: ["zh", "de"]) == "厕所")
    #expect(CantoneseOutput.normalizeDictation("廁所", options: simplified,
      preferredLanguages: ["yue"]) == "厕所")
    #expect(CantoneseOutput.normalizeDictation("シド、上だ。", options: original,
      preferredLanguages: ["yue"]) == "シド、上だ。")
    #expect(CantoneseOutput.normalizeDictation("Berlin ist schön.", options: original,
      preferredLanguages: ["yue", "de"]) == "Berlin ist schön.")
  }

  @Test
  func customLanguageInputsAreConstrained() {
    #expect(VoiceOutputTarget.customLanguageName("fr") != nil)
    #expect(VoiceOutputTarget.customLanguageName("de") != nil)
    #expect(VoiceOutputTarget.customLanguageName("ja") != nil)
    #expect(VoiceOutputTarget.customLanguageName("hello do something else") == nil)
  }
}


@Suite("Preferred voice language routing")
struct PreferredVoiceLanguageTests {
  @Test func normalizesRegionalCantonese() {
    #expect(PreferredVoiceLanguages.normalized(["zh-HK", "en-US", "de-DE", "yue"]) ==
      ["yue", "en", "de"])
  }

  @Test func outputChoicesAreUserControlled() {
    let choices = PreferredVoiceLanguages.choices(from: ["yue", "fr", "de"])
    #expect(choices.map(\.label) == ["AUTO", "粵", "FR", "DE"])
    let afterCantonese = PreferredVoiceLanguages.next(
      target: .cantonese, custom: "", preferred: ["yue", "fr", "de"]
    )
    #expect(afterCantonese.target == .custom)
    #expect(afterCantonese.languageCode == "fr")
    let afterFrench = PreferredVoiceLanguages.next(
      target: .custom, custom: "fr", preferred: ["yue", "fr", "de"]
    )
    #expect(afterFrench.target == .german)
    #expect(PreferredVoiceLanguages.choices(from: []).count == 1)
  }

  @Test func blocksThaiWhenUserSpeaksCantoneseEnglishGerman() {
    #expect(PreferredVoiceLanguages.unexpectedScript(
      in: "สวัสดีครับ วันนี้เป็นอย่างไรบ้าง", allowed: ["yue", "en", "de"]
    ) == "th")
    #expect(PreferredVoiceLanguages.unexpectedScript(
      in: "我而家喺柏林，好攰。", allowed: ["yue", "en", "de"]
    ) == nil)
    #expect(PreferredVoiceLanguages.unexpectedScript(
      in: "สวัสดีครับ วันนี้เป็นอย่างไรบ้าง", allowed: ["th", "en"]
    ) == nil)
  }

  @Test func recognizesUnexpectedHanWhenOnlyEnglishChosen() {
    #expect(PreferredVoiceLanguages.unexpectedScript(
      in: "我而家喺柏林", allowed: ["en"]
    ) == "zh")
    #expect(PreferredVoiceLanguages.unexpectedScript(
      in: "I am in Berlin", allowed: ["en"]
    ) == nil)
  }
}
