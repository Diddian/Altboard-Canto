import Foundation
import Testing

@Suite("Voice Compose")
struct VoiceComposePromptTests {
  @Test func recognizesFourLanguagesAndMedia() {
    #expect(VoiceComposeKind.detect(in: "幫我寫個 WhatsApp message 畀佢") == .whatsapp)
    #expect(VoiceComposeKind.detect(in: "Schreib mir eine WhatsApp Nachricht") == .whatsapp)
    #expect(VoiceComposeKind.detect(in: "Send a WhatsApp message") == .whatsapp)
    #expect(VoiceComposeKind.detect(in: "幫我寫封電郵俾學校") == .email)
    #expect(VoiceComposeKind.detect(in: "Schreibe einen Brief an den Vermieter") == .letter)
    #expect(VoiceComposeKind.detect(in: "Write a formal letter to my landlord") == .letter)
    #expect(VoiceComposeKind.detect(in: "我要寫一封信") == .letter)
    #expect(VoiceComposeKind.detect(in: "發個訊息畀朋友") == .message)
    #expect(VoiceComposeKind.detect(in: "I need to contact someone") == .unspecified)
  }

  @Test func selectedGermanOverridesSpokenLanguage() {
    let options = VoiceOutputConfiguration(cleanupEnabled: false, target: .german,
      register: .faithful, customLanguage: "")
    let result = VoiceComposePrompt.systemPrompt(for: options,
      spokenInstruction: "幫我寫個 WhatsApp message to my landlord")
    #expect(result.contains("OVERRIDING KEYBOARD OUTPUT LANGUAGE"))
    #expect(result.contains("German"))
    #expect(result.contains("WhatsApp"))
  }

  @Test func cantoneseDetectsUnconvertedEnglishAndFormalDrift() {
    #expect(VoiceComposePrompt.needsCantoneseRetry(output: "Hello again", target: .cantonese))
    #expect(VoiceComposePrompt.needsCantoneseRetry(output: "我們現在沒有時間", target: .cantonese))
    #expect(!VoiceComposePrompt.needsCantoneseRetry(output: "我哋而家冇時間", target: .cantonese))
    #expect(!VoiceComposePrompt.needsCantoneseRetry(output: "Hello again", target: .original))
  }
}
