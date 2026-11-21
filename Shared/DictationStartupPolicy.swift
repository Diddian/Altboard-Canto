import Foundation

/// The keyboard owns its request deadline; capture and finalization stay with
/// the containing app. This record contains no audio or input-field content.
enum DictationStartupPolicy {
  struct Request: Equatable, Sendable {
    let token: String
    let startedAt: TimeInterval
  }

  enum Decision: Equatable, Sendable {
    case finished, paused, waiting, processing, finishCapturedSpeech, expired
  }

  static let timeout: TimeInterval = 15
  static let modelLoadingTimeout: TimeInterval = 180
  private static let requestKey = "canto.dictationStartupRequest.v1"

  @discardableResult
  static func begin(
    token: String, now: TimeInterval, defaults: UserDefaults
  ) -> Bool {
    guard UUID(uuidString: token) != nil, now.isFinite, now > 0 else { return false }
    // A view recreation or repeated status request cannot extend the deadline.
    guard self.request(for: token, defaults: defaults) == nil else { return false }
    let value: [String: Any] = ["token": token, "startedAt": now]
    defaults.set(value, forKey: self.requestKey)
    return true
  }

  static func request(for token: String?, defaults: UserDefaults) -> Request? {
    guard let token, UUID(uuidString: token) != nil,
          let value = defaults.dictionary(forKey: self.requestKey),
          value["token"] as? String == token,
          let startedAt = value["startedAt"] as? TimeInterval,
          startedAt.isFinite, startedAt > 0 else { return nil }
    return Request(token: token, startedAt: startedAt)
  }

  static func clear(matching token: String?, defaults: UserDefaults) {
    guard self.request(for: token, defaults: defaults) != nil else { return }
    defaults.removeObject(forKey: self.requestKey)
  }

  static func decision(
    request: Request, currentToken: String?, cancelled: Bool,
    visible: Bool, captureAcknowledged: Bool, recordedFrames: Bool,
    recentAudioHeartbeat: Bool, currentProgress: Bool, stopRequested: Bool,
    modelLoading: Bool, now: TimeInterval
  ) -> Decision {
    guard request.token == currentToken, !cancelled else { return .finished }
    if captureAcknowledged { return .finished }
    if currentProgress || stopRequested { return .processing }
    // Opening the containing app can hide the keyboard while capture starts.
    // A disappearing view must never cancel that handoff or captured speech.
    guard visible else { return .paused }
    let elapsed = now.isFinite && request.startedAt.isFinite && now >= request.startedAt
      ? now - request.startedAt : self.modelLoadingTimeout
    if recordedFrames {
      // The app has confirmed frames, but its notification was missed. Keep
      // the audio even if an interruption has since stopped its heartbeat.
      // Normal finalization owns captured speech; startup cannot discard it.
      return elapsed >= self.timeout ? .finishCapturedSpeech : .waiting
    }
    // A persisted loading flag can survive a terminated app. Extend only
    // while the live audio heartbeat proves the host is still running.
    let limit = modelLoading && recentAudioHeartbeat ? self.modelLoadingTimeout : self.timeout
    return elapsed >= limit ? .expired : .waiting
  }
}
