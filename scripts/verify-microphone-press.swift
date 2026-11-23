import Foundation

@main
struct VerifyMicrophonePress {
  static func main() {
    var gesture = MicrophonePressPolicy()
    precondition(!gesture.isActive)
    precondition(gesture.begin(at: 10, state: .idle))
    precondition(gesture.isActive)
    precondition(!gesture.begin(at: 10.02, state: .idle))
    precondition(!gesture.activateHold(at: 10.2))
    precondition(gesture.release(at: 10.21) == .tap)
    precondition(!gesture.isActive)
    precondition(gesture.release(at: 10.5) == .none)

    precondition(gesture.begin(at: 20, state: .idle))
    precondition(gesture.activateHold(at: 20.3))
    precondition(!gesture.activateHold(at: 20.4))
    precondition(gesture.release(at: 21.8) == .stop)

    precondition(gesture.begin(at: 30, state: .idle))
    precondition(gesture.release(at: 30.4) == .startThenStop)

    precondition(gesture.begin(at: 40, state: .recording))
    precondition(!gesture.activateHold(at: 40.4))
    precondition(gesture.release(at: 40.5) == .stop)

    precondition(gesture.begin(at: 50, state: .recording))
    precondition(gesture.release(at: 50.1) == .tap)
    precondition(gesture.begin(at: 60, state: .starting))
    precondition(gesture.release(at: 60.5) == .stop)
    precondition(gesture.begin(at: 70, state: .locked))
    precondition(gesture.release(at: 70.5) == .tap)
    precondition(gesture.begin(at: 80, state: .idle))
    gesture.cancel()
    precondition(gesture.release(at: 81) == .none)

    let suite = "altboard.test.mic.hold." + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No test defaults") }
    defer { defaults.removePersistentDomain(forName: suite) }
    precondition(!MicrophoneHoldStopIntent.request(for: nil, defaults: defaults))
    precondition(MicrophoneHoldStopIntent.request(for: "session-a", defaults: defaults))
    precondition(!MicrophoneHoldStopIntent.consume(for: "session-b", defaults: defaults))
    precondition(MicrophoneHoldStopIntent.isRequested(for: "session-a", defaults: defaults))
    precondition(MicrophoneHoldStopIntent.consume(for: "session-a", defaults: defaults))
    precondition(!MicrophoneHoldStopIntent.consume(for: "session-a", defaults: defaults))
    precondition(MicrophoneHoldStopIntent.request(for: "old-session", defaults: defaults))
    MicrophoneHoldStopIntent.clear(defaults: defaults)
    precondition(!MicrophoneHoldStopIntent.isRequested(for: "old-session", defaults: defaults))

    // Fresh UIKit controllers can recover the same field without persisting its ID.
    let token = UUID().uuidString
    let field = UUID()
    let fingerprint = DictationRequestPolicy.destinationFingerprint(
      sessionToken: token, document: field
    )
    precondition(fingerprint != nil)
    precondition(DictationRequestPolicy.isSameDestination(
      sessionToken: token, document: field, fingerprint: fingerprint
    ))
    precondition(!DictationRequestPolicy.isSameDestination(
      sessionToken: token, document: UUID(), fingerprint: fingerprint
    ))
    precondition(!DictationRequestPolicy.isSameDestination(
      sessionToken: UUID().uuidString, document: field, fingerprint: fingerprint
    ))
    precondition(!DictationRequestPolicy.isSameDestination(
      sessionToken: token, document: nil, fingerprint: fingerprint
    ))
    precondition(DictationRequestPolicy.destinationFingerprint(
      sessionToken: nil, document: field
    ) == nil)
    // Even a matching document cannot substitute for continuously held focus.
    let epoch = UUID()
    let focused = DictationRequestPolicy.Focus(
      document: field, epoch: epoch, before: "粵語 und English", after: " Ende"
    )
    precondition(focused.matches(focused))
    precondition(!focused.matches(nil))
    precondition(!focused.matches(.init(
      document: UUID(), epoch: epoch, before: "粵語 und English", after: " Ende"
    )))
    precondition(!focused.matches(.init(
      document: field, epoch: UUID(), before: "粵語 und English", after: " Ende"
    )))
    precondition(!focused.matches(.init(
      document: field, epoch: epoch, before: "粵語 und", after: " English Ende"
    )))
    precondition(!focused.matches(.init(
      document: field, epoch: epoch, before: "粵語 und English", after: " Start"
    )))
    let origin = DictationRequestPolicy.originProcessMarker(
      token: token, process: (pid: 1234, version: 7)
    )
    precondition(origin != nil)
    // A matching host process does not prove that the original field is focused.
    precondition(DictationRequestPolicy.originProcessMarker(
      token: token, process: (pid: 1234, version: 7)
    ) == origin)
    precondition(DictationRequestPolicy.originProcessMarker(
      token: token, process: (pid: 1235, version: 7)
    ) != origin)
    precondition(DictationRequestPolicy.originProcessMarker(
      token: nil, process: (pid: 1234, version: 7)
    ) == nil)
    precondition(LiveDictationChunkPolicy.firstWindowOptions.first == 1_600)
    precondition(LiveDictationChunkPolicy.retryFirstWindow(after: 1_600) == 3_200)
    let gib: UInt64 = 1_073_741_824
    precondition(LiveDictationChunkPolicy.defaultFirstWindowSamples(physicalMemoryBytes: 12 * gib) == 1_600)
    precondition(LiveDictationChunkPolicy.defaultFirstWindowSamples(physicalMemoryBytes: 8 * gib) == 3_200)
    precondition(LiveDictationChunkPolicy.defaultFirstWindowSamples(physicalMemoryBytes: 6 * gib) == 8_000)
    precondition(LiveDictationChunkPolicy.defaultFirstWindowSamples(physicalMemoryBytes: 4 * gib) == 24_000)
    precondition(DictationRequestPolicy.shouldRequestWarmSession(
      keyboardActive: false, appActive: true, heartbeat: 1, now: 10,
      practiceFocused: false
    ))
    precondition(DictationRequestPolicy.shouldRequestWarmSession(
      keyboardActive: false, appActive: false, heartbeat: 9.5, now: 10,
      practiceFocused: false
    ))
    precondition(!DictationRequestPolicy.shouldRequestWarmSession(
      keyboardActive: false, appActive: false, heartbeat: 1, now: 10,
      practiceFocused: false
    ))
    // A stale persisted recording must not trap the next microphone press.
    // Neither a late callback, cancellation nor a live audio tap may create
    // another capture owner.
    precondition(DictationRequestPolicy.shouldRestartUnacknowledgedRecording(
      requestToken: token, currentToken: token, cancelled: false,
      acknowledged: false, heartbeat: 1, now: 10
    ))
    precondition(!DictationRequestPolicy.shouldRestartUnacknowledgedRecording(
      requestToken: token, currentToken: token, cancelled: false,
      acknowledged: false, heartbeat: 9.5, now: 10
    ))
    precondition(!DictationRequestPolicy.shouldRestartUnacknowledgedRecording(
      requestToken: token, currentToken: token, cancelled: false,
      acknowledged: true, heartbeat: 1, now: 10
    ))
    precondition(!DictationRequestPolicy.shouldRestartUnacknowledgedRecording(
      requestToken: token, currentToken: token, cancelled: true,
      acknowledged: false, heartbeat: 1, now: 10
    ))
    precondition(!DictationRequestPolicy.shouldRestartUnacknowledgedRecording(
      requestToken: token, currentToken: UUID().uuidString, cancelled: false,
      acknowledged: false, heartbeat: 1, now: 10
    ))
    print("Microphone tap, hold, release and token-scoped stop checks passed")
  }
}
