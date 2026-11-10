import Foundation

/// A single captured turn. Only source/translated text and the user's chosen
/// speaker/target are saved. ASR language is an estimate, not a speaker ID.
enum ConversationSpeaker: String, Codable, Sendable, CaseIterable {
  case other, me

  var title: String {
    switch self {
    case .other: "Other person"
    case .me: "You"
    }
  }
}

struct ConversationTurn: Identifiable, Codable, Sendable {
  let id: UUID
  let speaker: ConversationSpeaker
  let audioFileName: String
  let duration: TimeInterval
  let targetCode: String
  var sourceText: String
  var cleanedSourceText: String? = nil
  var translatedText: String?
  var detectedLanguageCode: String?
  var status: String

  var needsRetry: Bool { status != "translated" && status != "original" }
}


enum ConversationTurnPolicy {
  /// A folder import may never resolve a filename outside its own audio dir.
  static func validAudioFileName(_ name: String) -> Bool {
    name.range(of: "^[A-Fa-f0-9-]{36}\\.caf$", options: .regularExpression) != nil
  }

  static func validOutput(target: VoiceOutputTarget, custom: String) -> Bool {
    target != .custom || VoiceOutputTarget.customLanguageName(custom) != nil
  }
}
