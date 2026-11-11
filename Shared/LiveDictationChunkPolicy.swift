/// 16 kHz audio: first-window experiments are deliberately user-selected
/// in Diagnostics. Keep a single decoder, no concurrent Qwen inference.
enum LiveDictationChunkPolicy {
  static let firstQwenSamples = 24_000
  static let subsequentQwenSamples = 24_000
  static let otherEngineSamples = 48_000
  static let firstWindowOptions = [1_600, 3_200, 8_000, 16_000, 24_000]

  static func samples(isQwen: Bool, hasAttemptedFirst: Bool,
                      firstWindowSamples: Int = firstQwenSamples) -> Int {
    guard isQwen else { return otherEngineSamples }
    if hasAttemptedFirst { return subsequentQwenSamples }
    return firstWindowOptions.contains(firstWindowSamples)
      ? firstWindowSamples : firstQwenSamples
  }

  /// Reuse the same captured start of speech after a too-short window
  /// produces no text. No initial audio is consumed before escalation.
  static func retryFirstWindow(after samples: Int) -> Int? {
    firstWindowOptions.first { $0 > samples }
  }
}
