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
