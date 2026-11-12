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
    // Completed output must not jump into a new host field, even when
    // the main app already cleared its mutable active session token.
    let epoch = UUID()
    func mayRecover(
      token: String? = nil, active: String? = nil,
      delivery: String = tokenForCompleted,
      currentDocument: UUID? = field, epochID: UUID? = epoch,
      cancelled: Bool = false, recording: Bool = false,
      hasSelection: Bool = false
    ) -> Bool {
      DictationRequestPolicy.mayRecoverCompleted(
        requestedToken: token, activeToken: active,
        deliveryToken: delivery, deliveryEpoch: epochID,
        currentDocument: currentDocument, fingerprint: fingerprint,
        recording: recording, cancelled: cancelled,
        hasSelection: hasSelection
      )
    }
    let tokenForCompleted = token
    precondition(mayRecover())
    precondition(!mayRecover(token: token))
    precondition(!mayRecover(active: token))
    precondition(!mayRecover(delivery: UUID().uuidString))
    precondition(!mayRecover(currentDocument: UUID()))
    precondition(!mayRecover(currentDocument: nil))
    precondition(!mayRecover(epochID: nil))
    precondition(!mayRecover(cancelled: true))
    precondition(!mayRecover(recording: true))
    precondition(!mayRecover(hasSelection: true))
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
    precondition(!DictationRequestPolicy.shouldRequestWarmSession(
      keyboardActive: false, appActive: false, heartbeat: 1, now: 10,
      practiceFocused: false
    ))
    print("Microphone tap, hold, release and token-scoped stop checks passed")
  }
}
