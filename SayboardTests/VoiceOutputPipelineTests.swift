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
  func keyboardCyclesOutputLanguages() {
    #expect(VoiceOutputTarget.nextKeyboardTarget(after: .original) == .cantonese)
    #expect(VoiceOutputTarget.nextKeyboardTarget(after: .cantonese) == .english)
    #expect(VoiceOutputTarget.nextKeyboardTarget(after: .english) == .german)
    #expect(VoiceOutputTarget.nextKeyboardTarget(after: .german) == .original)
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
