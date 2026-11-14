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

enum ConversationTurnState: String, Codable, Sendable {
  case recording, processing, speechFailed, noSpeech, transcribed
  case original, translationFailed, translated, interrupted

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: value) ?? .interrupted
  }
}

struct ConversationDraft: Codable {
  let schemaVersion: Int
  var turns: [ConversationTurn]
}

struct ConversationTurn: Identifiable, Codable, Sendable, Equatable {
  let id: UUID
  let speaker: ConversationSpeaker
  let audioFileName: String
  var duration: TimeInterval
  let targetCode: String
  var sourceText: String
  var cleanedSourceText: String? = nil
  var translatedText: String?
  var detectedLanguageCode: String?
  var status: ConversationTurnState

  var needsRetry: Bool { status != .translated && status != .original }
}


enum ConversationTurnPolicy {
  static let maximumCaptureSeconds: TimeInterval = 25
  static let maximumRecoverySeconds: TimeInterval = 35
  /// A folder import may never resolve a filename outside its own audio dir.
  static func validAudioFileName(_ name: String) -> Bool {
    name.range(of: "^[A-Fa-f0-9-]{36}\\.caf$", options: .regularExpression) != nil
  }

  static func validOutput(target: VoiceOutputTarget, custom: String) -> Bool {
    target != .custom || VoiceOutputTarget.customLanguageName(custom) != nil
  }
}

