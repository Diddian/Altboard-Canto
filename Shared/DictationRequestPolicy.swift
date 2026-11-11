import Foundation

enum DictationRequestPolicy {
  static func isCurrent(started: String?, current: String?, cancelled: Bool) -> Bool {
    guard let started, !started.isEmpty, !cancelled else { return false }
    return started == current
  }

  /// Recent heartbeats are emitted by the main app's running audio input tap.
  /// Ignore stale shared state left by a suspended or terminated process.
  static func hasRecentAudioHeartbeat(_ value: TimeInterval, now: TimeInterval) -> Bool {
    value > 0 && now >= value && now - value <= 3
  }

  static func shouldRequestWarmSession(
    keyboardActive: Bool, appActive: Bool, heartbeat: TimeInterval,
    now: TimeInterval, practiceFocused: Bool
  ) -> Bool {
    practiceFocused || (hasRecentAudioHeartbeat(heartbeat, now: now)
      && (keyboardActive || appActive))
  }

  static func shouldOpenColdFallback(
    requestToken: String?, currentToken: String?, cancelled: Bool,
    keyboardVisible: Bool, recording: Bool, appAcknowledged: Bool,
    heartbeat: TimeInterval, now: TimeInterval
  ) -> Bool {
    isCurrent(started: requestToken, current: currentToken, cancelled: cancelled)
      && keyboardVisible && !recording && !appAcknowledged
      && !hasRecentAudioHeartbeat(heartbeat, now: now)
  }

}
