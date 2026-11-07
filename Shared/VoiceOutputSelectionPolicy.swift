/// Dictation output belongs to the latest selected language, not to the
/// language shown when the microphone started. Never deliver stale output.
enum VoiceOutputSelectionPolicy {
  enum Decision: Equatable {
    case deliver
    case retry
    case reject
  }

  static let maximumAttempts = 3

  static func decide<Options: Equatable>(
    processed: Options, current: Options, attempt: Int
  ) -> Decision {
    if processed == current { return .deliver }
    return attempt < maximumAttempts ? .retry : .reject
  }
}
