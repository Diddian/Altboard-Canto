import Foundation

/// One microphone press supports both the original tap toggle and hold-to-talk.
/// The view owns only the gesture; the containing app still owns audio and ASR.
struct MicrophonePressPolicy {
  enum InitialState: Equatable {
    case idle
    case starting
    case recording
    case locked
  }

  enum ReleaseAction: Equatable {
    case none
    case tap
    case stop
    case startThenStop
  }

  static let holdThreshold: TimeInterval = 0.28

  private var beganAt: TimeInterval?
  private var initialState = InitialState.idle
  private var startedOnHold = false

  var isActive: Bool { beganAt != nil }

  mutating func begin(at time: TimeInterval, state: InitialState) -> Bool {
    guard beganAt == nil else { return false }
    beganAt = time
    initialState = state
    startedOnHold = false
    return true
  }

  /// Called once after the threshold while the finger is still held.
  mutating func activateHold(at time: TimeInterval) -> Bool {
    guard let beganAt, initialState == .idle, !startedOnHold,
          time - beganAt >= Self.holdThreshold else { return false }
    startedOnHold = true
    return true
  }

  mutating func release(at time: TimeInterval) -> ReleaseAction {
    guard let beganAt else { return .none }
    let held = startedOnHold || time - beganAt >= Self.holdThreshold
    let action: ReleaseAction
    switch initialState {
    case .idle:
      action = startedOnHold ? .stop : held ? .startThenStop : .tap
    case .starting, .recording:
      action = held ? .stop : .tap
    case .locked:
      action = .tap
    }
    cancel()
    return action
  }

  mutating func cancel() {
    beganAt = nil
    initialState = .idle
    startedOnHold = false
  }
}

/// Short-lived, token-scoped stop intent survives a late capture acknowledgement.
/// It holds no audio, transcript, host text or gesture path.
enum MicrophoneHoldStopIntent {
  private static let key = "canto.dictation.holdStopSession.v1"

  @discardableResult
  static func request(for token: String?, defaults: UserDefaults) -> Bool {
    guard let token, !token.isEmpty else { return false }
    defaults.set(token, forKey: key)
    defaults.synchronize()
    return true
  }

  static func isRequested(for token: String?, defaults: UserDefaults) -> Bool {
    guard let token, !token.isEmpty else { return false }
    defaults.synchronize()
    return defaults.string(forKey: key) == token
  }

  static func consume(for token: String?, defaults: UserDefaults) -> Bool {
    guard isRequested(for: token, defaults: defaults) else { return false }
    clear(defaults: defaults)
    return true
  }

  static func clear(defaults: UserDefaults) {
    defaults.removeObject(forKey: key)
    defaults.synchronize()
  }
}
