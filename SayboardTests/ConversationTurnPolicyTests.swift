import Foundation
import Testing

@Suite("Offline conversation turn persistence and language selection")
struct ConversationTurnPolicyTests {
  @Test func validAudioIdentifiersRejectTraversal() {
    #expect(ConversationTurnPolicy.validAudioFileName(
      "110E8400-E29B-41D4-A716-446655440000.caf"))
    for name in ["../private.caf", "/tmp/a.caf", "recording.caf",
                 "110E8400-E29B-41D4-A716-446655440000.txt", ""] {
      #expect(!ConversationTurnPolicy.validAudioFileName(name))
    }
  }

  @Test func customTranslationLanguagesUseExplicitCodes() {
    #expect(ConversationTurnPolicy.validOutput(target: .cantonese, custom: ""))
    #expect(ConversationTurnPolicy.validOutput(target: .custom, custom: "tr"))
    #expect(ConversationTurnPolicy.validOutput(target: .custom, custom: "ja"))
    #expect(ConversationTurnPolicy.validOutput(target: .custom, custom: "ar"))
    #expect(!ConversationTurnPolicy.validOutput(target: .custom, custom: ""))
    #expect(!ConversationTurnPolicy.validOutput(target: .custom, custom: "../tr"))
  }

  @Test func savedOriginalAndTranslationSurviveRoundTrip() throws {
    let fixture = ConversationTurn(
      id: UUID(), speaker: .other,
      audioFileName: "110E8400-E29B-41D4-A716-446655440000.caf",
      duration: 4.2, targetCode: "yue",
      sourceText: "Merhaba, nasılsın?",
      translatedText: "你好，你點呀？",
      detectedLanguageCode: "tr", status: .translated
    )
    let data = try JSONEncoder().encode([fixture])
    let decoded = try JSONDecoder().decode([ConversationTurn].self, from: data)
    #expect(decoded.count == 1)
    #expect(decoded[0].speaker == .other)
    #expect(decoded[0].sourceText == fixture.sourceText)
    #expect(decoded[0].cleanedSourceText == nil)
    #expect(decoded[0].translatedText == fixture.translatedText)
    #expect(decoded[0].targetCode == "yue")
    #expect(!decoded[0].needsRetry)
  }

  @Test func cleanedSpeechSurvivesRoundTripAndKeepsOriginal() throws {
    var fixture = ConversationTurn(
      id: UUID(), speaker: .other,
      audioFileName: "110E8400-E29B-41D4-A716-446655440000.caf",
      duration: 2, targetCode: "yue",
      sourceText: "Ich habe, äh, morgen Zeit.",
      translatedText: "我聽日得閒。",
      detectedLanguageCode: "de", status: .translated
    )
    fixture.cleanedSourceText = "Ich habe morgen Zeit."
    let decoded = try JSONDecoder().decode(ConversationTurn.self,
      from: JSONEncoder().encode(fixture))
    #expect(decoded.sourceText == fixture.sourceText)
    #expect(decoded.cleanedSourceText == "Ich habe morgen Zeit.")
  }

  @Test func originalLanguageDoesNotNeedTranslatedText() {
    let turn = ConversationTurn(
      id: UUID(), speaker: .me,
      audioFileName: "110E8400-E29B-41D4-A716-446655440000.caf",
      duration: 2, targetCode: "",
      sourceText: "مرحبا", translatedText: nil,
      detectedLanguageCode: "ar", status: .original
    )
    #expect(!turn.needsRetry)
    #expect(turn.translatedText == nil)
    #expect(turn.sourceText == "مرحبا")
  }

  @Test func failedTranslationsRemainRetryableAndKeepOriginal() {
    let turn = ConversationTurn(
      id: UUID(), speaker: .me,
      audioFileName: "110E8400-E29B-41D4-A716-446655440000.caf",
      duration: 1.8, targetCode: "tr",
      sourceText: "我想去飲咖啡。",
      translatedText: nil, detectedLanguageCode: "zh",
      status: .translationFailed
    )
    #expect(turn.needsRetry)
    #expect(turn.sourceText == "我想去飲咖啡。")
    #expect(turn.translatedText == nil)
  }
}

