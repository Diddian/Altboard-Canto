/// Audio frames are 16 kHz. Keep the first usable chunk short without
/// running concurrent Qwen3 decode jobs that compete for CPU and memory.
enum LiveDictationChunkPolicy {
  // Restore the 1.5-second first chunk used by the stable #84/#146 pipeline.
  // One second frequently contains too little phonetic context for Qwen3.
  static let firstQwenSamples = 24_000
  static let subsequentQwenSamples = 24_000
  static let otherEngineSamples = 48_000

  static func samples(isQwen: Bool, hasAttemptedFirst: Bool) -> Int {
    guard isQwen else { return otherEngineSamples }
    return hasAttemptedFirst ? subsequentQwenSamples : firstQwenSamples
  }
}
