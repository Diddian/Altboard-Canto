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

  /// Compatibility marker for diagnostics and request provenance only.
  /// The same host process can own different fields: never use this as
  /// authorization to insert text without a UIKit document identifier.
  static func originProcessMarker(
    token: String?, process: (pid: Int, version: Int)?
  ) -> String? {
    guard let token, UUID(uuidString: token) != nil,
          let process, process.pid > 0 else { return nil }
    let input = Data("altboard-host-v1:\(token):\(process.pid):\(process.version)".utf8)
    return Data(SHA256.hash(data: input)).base64EncodedString()
  }

  /// A controller-local snapshot. Never put host context in App Group or diagnostics.
  struct Focus: Equatable {
    let document: UUID
    let epoch: UUID
    private let before: String
    private let after: String

    init(document: UUID, epoch: UUID, before: String?, after: String?) {
      self.document = document
      self.epoch = epoch
      self.before = String((before ?? "").suffix(48))
      self.after = String((after ?? "").prefix(48))
    }

    func matches(_ current: Focus?) -> Bool {
      current == self
    }
  }

  /// Keep the originating keyboard request across a cold containing-app
  /// launch. The destination proof and session token must not be reset while
  /// that fresh request is being handed off.
  static func shouldPreserveColdStartRequest(
    token: String?, isRecentKeyboardRequest: Bool, cancelled: Bool
  ) -> Bool {
    guard isRecentKeyboardRequest, !cancelled,
          let token, UUID(uuidString: token) != nil else { return false }
    return true
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

  /// Persisted lifecycle flags and an idle audio tap cannot acknowledge capture.
  static func mayShowRecording(
    requestToken: String?, currentToken: String?, cancelled: Bool,
    recording: Bool, sessionActive: Bool, captureAcknowledged: Bool,
    heartbeat: TimeInterval, now: TimeInterval
  ) -> Bool {
    guard let requestToken, UUID(uuidString: requestToken) != nil else { return false }
    return isCurrent(started: requestToken, current: currentToken, cancelled: cancelled)
      && recording && sessionActive && captureAcknowledged
      && hasRecentAudioHeartbeat(heartbeat, now: now)
  }

  static func shouldRequestWarmSession(
    keyboardActive: Bool, appActive: Bool, heartbeat: TimeInterval,
    now: TimeInterval, practiceFocused: Bool, modelLoading: Bool = false
  ) -> Bool {
    // Try the app-owned session first even if iOS paused an idle heartbeat.
    // A bounded handshake will detect stale state and open the app if needed.
    // A live audio heartbeat is stronger than a temporarily stale UI flag.
    // This only selects a bounded host handshake; no heartbeat can acknowledge
    // a new recording request on its own.
    practiceFocused || appActive || keyboardActive || modelLoading
      || hasRecentAudioHeartbeat(heartbeat, now: now)
  }

  /// Replacement of a persisted recording requires both a missing
  /// request-scoped capture acknowledgment and a stale real audio heartbeat.
  /// A healthy input tap is never rearmed using an old document token.
  static func shouldRestartUnacknowledgedRecording(
    requestToken: String?, currentToken: String?, cancelled: Bool,
    acknowledged: Bool, heartbeat: TimeInterval, now: TimeInterval
  ) -> Bool {
    isCurrent(started: requestToken, current: currentToken, cancelled: cancelled)
      && !acknowledged && !hasRecentAudioHeartbeat(heartbeat, now: now)
  }

  static func shouldOpenColdFallback(
    requestToken: String?, currentToken: String?, cancelled: Bool,
    keyboardVisible: Bool, recording: Bool, appAcknowledged: Bool,
    heartbeat: TimeInterval, now: TimeInterval
  ) -> Bool {
    // Liveness is not an acknowledgment for this particular request.
    // An unacknowledged start must eventually use the bounded fallback.
    _ = heartbeat
    _ = now
    return isCurrent(started: requestToken, current: currentToken, cancelled: cancelled)
      && keyboardVisible && !recording && !appAcknowledged
  }

}
