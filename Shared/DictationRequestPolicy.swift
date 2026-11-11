import Foundation
import CryptoKit

enum DictationRequestPolicy {
  /// An ephemeral request-bound fingerprint identifies only the input field.
  /// Never persist or log a UIKit document UUID or any host text.
  static func destinationFingerprint(sessionToken: String?, document: UUID?) -> String? {
    guard let sessionToken, UUID(uuidString: sessionToken) != nil,
          let document else { return nil }
    let input = Data("altboard-destination-v1:\(sessionToken):\(document.uuidString)".utf8)
    return Data(SHA256.hash(data: input)).base64EncodedString()
  }

  static func isSameDestination(
    sessionToken: String?, document: UUID?, fingerprint: String?
  ) -> Bool {
    guard let fingerprint, !fingerprint.isEmpty,
          let actual = destinationFingerprint(sessionToken: sessionToken, document: document)
    else { return false }
    return actual == fingerprint
  }

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
    // Try the app-owned session first even if iOS paused an idle heartbeat.
    // A bounded handshake will detect stale state and open the app if needed.
    practiceFocused || appActive
      || (keyboardActive && hasRecentAudioHeartbeat(heartbeat, now: now))
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
