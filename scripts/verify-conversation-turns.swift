import Foundation

@main
struct VerifyConversationTurns {
  static func main() throws {
    precondition(ConversationTurnPolicy.maximumCaptureSeconds == 25)
    precondition(ConversationTurnPolicy.maximumRecoverySeconds == 35)
    precondition(ConversationTurnPolicy.recoverySampleRate == 16_000)
    precondition(ConversationTurnPolicy.maximumRecoverySamples == 560_000)
    for sampleRate in [16_000.0, 44_100.0, 48_000.0] {
      for seconds in [25.0, 26.0, 35.0] {
        precondition(ConversationTurnPolicy.canRecoverAudio(
          frameCount: Int64(seconds * sampleRate), sampleRate: sampleRate
        ))
        precondition(ConversationTurnPolicy.canAppendRecoverySamples(
          Int(seconds * 16_000), to: 0
        ))
      }
      precondition(!ConversationTurnPolicy.canRecoverAudio(
        frameCount: Int64(35 * sampleRate) + 1, sampleRate: sampleRate
      ))
    }
    for sampleRate in [0, -16_000, Double.nan, Double.infinity, -Double.infinity] {
      precondition(!ConversationTurnPolicy.canRecoverAudio(frameCount: 1, sampleRate: sampleRate))
    }
    precondition(!ConversationTurnPolicy.canRecoverAudio(frameCount: -1, sampleRate: 16_000))
    precondition(!ConversationTurnPolicy.canRecoverAudio(
      frameCount: Int64.max, sampleRate: Double.leastNonzeroMagnitude
    ))
    precondition(ConversationTurnPolicy.canAppendRecoverySamples(1, to: 559_999))
    precondition(ConversationTurnPolicy.canAppendRecoverySamples(1, to: 416_000))
    precondition(ConversationTurnPolicy.canAppendRecoverySamples(160_000, to: 400_000))
    precondition(!ConversationTurnPolicy.canAppendRecoverySamples(1, to: 560_000))
    precondition(!ConversationTurnPolicy.canAppendRecoverySamples(160_001, to: 400_000))
    precondition(!ConversationTurnPolicy.canAppendRecoverySamples(560_001, to: 0))
    precondition(!ConversationTurnPolicy.canAppendRecoverySamples(Int.max, to: 1))
    precondition(!ConversationTurnPolicy.canAppendRecoverySamples(-1, to: 0))
    precondition(!ConversationTurnPolicy.canAppendRecoverySamples(0, to: -1))
    precondition(!ConversationTurnPolicy.canAppendRecoverySamples(0, to: 560_001))

    let good = "110E8400-E29B-41D4-A716-446655440000.caf"
    precondition(ConversationTurnPolicy.validAudioFileName(good))
    for invalid in ["../file.caf", "/private/file.caf", "test.caf",
                    "110E8400-E29B-41D4-A716-446655440000.txt"] {
      precondition(!ConversationTurnPolicy.validAudioFileName(invalid))
    }
    for code in ["tr", "ja", "ar", "yue", "en", "de"] {
      precondition(ConversationTurnPolicy.validOutput(target: .custom, custom: code))
    }
    precondition(!ConversationTurnPolicy.validOutput(target: .custom, custom: ""))
    let old = ConversationTurn(
      id: UUID(), speaker: .other, audioFileName: good,
      duration: 3.5, targetCode: "yue",
      sourceText: "Merhaba, nasılsın?", translatedText: "你好，你點呀？",
      detectedLanguageCode: "tr", status: .translated
    )
    let encoded = try JSONEncoder().encode([old])
    let decoded = try JSONDecoder().decode([ConversationTurn].self, from: encoded)
    precondition(decoded.count == 1 && decoded[0].sourceText == old.sourceText)
    precondition(decoded[0].translatedText == old.translatedText)
    precondition(!decoded[0].needsRetry)
    print("Conversation turn policy and preservation: PASS")
  }
}

