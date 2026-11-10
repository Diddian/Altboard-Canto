import Foundation

@main
struct VerifyConversationTurns {
  static func main() throws {
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
      detectedLanguageCode: "tr", status: "translated"
    )
    let encoded = try JSONEncoder().encode([old])
    let decoded = try JSONDecoder().decode([ConversationTurn].self, from: encoded)
    precondition(decoded.count == 1 && decoded[0].sourceText == old.sourceText)
    precondition(decoded[0].translatedText == old.translatedText)
    precondition(!decoded[0].needsRetry)
    print("Conversation turn policy and preservation: PASS")
  }
}
