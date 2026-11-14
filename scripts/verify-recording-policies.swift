import Foundation

@main
struct RecordingPolicyChecks {
  static func main() {
    precondition(DictationRequestPolicy.isCurrent(started: "a", current: "a", cancelled: false))
    precondition(!DictationRequestPolicy.isCurrent(started: "a", current: "a", cancelled: true))
    precondition(!DictationRequestPolicy.isCurrent(started: "a", current: "b", cancelled: false))
    precondition(!DictationRequestPolicy.isCurrent(started: nil, current: nil, cancelled: false))
    precondition(!DictationRequestPolicy.isCurrent(started: "", current: "", cancelled: false))
    precondition(!DictationRequestPolicy.isCurrent(started: "a", current: nil, cancelled: false))

    let validColdToken = UUID().uuidString
    precondition(DictationRequestPolicy.shouldPreserveColdStartRequest(
      token: validColdToken, isRecentKeyboardRequest: true, cancelled: false
    ))
    precondition(!DictationRequestPolicy.shouldPreserveColdStartRequest(
      token: validColdToken, isRecentKeyboardRequest: false, cancelled: false
    ))
    precondition(!DictationRequestPolicy.shouldPreserveColdStartRequest(
      token: validColdToken, isRecentKeyboardRequest: true, cancelled: true
    ))
    precondition(!DictationRequestPolicy.shouldPreserveColdStartRequest(
      token: nil, isRecentKeyboardRequest: true, cancelled: false
    ))
    precondition(!DictationRequestPolicy.shouldPreserveColdStartRequest(
      token: "stale-invalid-token", isRecentKeyboardRequest: true, cancelled: false
    ))
    let now: TimeInterval = 20
    let p = DictationRequestPolicy.self
    precondition(p.hasRecentAudioHeartbeat(19.5, now: now))
    precondition(p.hasRecentAudioHeartbeat(17, now: now))
    precondition(!p.hasRecentAudioHeartbeat(16.9, now: now))
    precondition(!p.hasRecentAudioHeartbeat(20.1, now: now))
    precondition(!p.hasRecentAudioHeartbeat(0, now: now))
    precondition(p.shouldRequestWarmSession(
      keyboardActive: false, appActive: true, heartbeat: 19.5,
      now: now, practiceFocused: false
    ))
    precondition(p.shouldRequestWarmSession(
      keyboardActive: true, appActive: false, heartbeat: 19.5,
      now: now, practiceFocused: false
    ))
    precondition(p.shouldRequestWarmSession(
      keyboardActive: false, appActive: false, heartbeat: 0,
      now: now, practiceFocused: true
    ))
    // A live app-owned session must get a bounded warm handshake even if
    // iOS paused its idle audio heartbeat while the user switched apps.
    precondition(p.shouldRequestWarmSession(
      keyboardActive: true, appActive: true, heartbeat: 16.9,
      now: now, practiceFocused: false
    ))
    precondition(p.shouldRequestWarmSession(
      keyboardActive: false, appActive: false, heartbeat: 19.5,
      now: now, practiceFocused: false
    ))
    precondition(!p.shouldRequestWarmSession(
      keyboardActive: false, appActive: false, heartbeat: 16.9,
      now: now, practiceFocused: false
    ))
    func cold(
      token: String? = "request", current: String? = "request",
      cancelled: Bool = false, visible: Bool = true,
      recording: Bool = false, acknowledged: Bool = false,
      heartbeat: TimeInterval = 16.9
    ) -> Bool {
      p.shouldOpenColdFallback(
        requestToken: token, currentToken: current, cancelled: cancelled,
        keyboardVisible: visible, recording: recording,
        appAcknowledged: acknowledged, heartbeat: heartbeat, now: now
      )
    }
    precondition(cold())
    precondition(!cold(token: "old"))
    precondition(!cold(current: nil))
    precondition(!cold(cancelled: true))
    precondition(!cold(visible: false))
    precondition(!cold(recording: true))
    precondition(!cold(acknowledged: true))
    // A heartbeat never acknowledges this particular request.
    precondition(cold(heartbeat: 19.5))


    let deliveryToken = UUID().uuidString
    let sourceDocument = UUID()
    let proof = p.destinationFingerprint(sessionToken: deliveryToken, document: sourceDocument)
    precondition(proof != nil)
    precondition(p.isSameDestination(sessionToken: deliveryToken,
      document: sourceDocument, fingerprint: proof))
    precondition(!p.isSameDestination(sessionToken: deliveryToken,
      document: nil, fingerprint: proof))
    precondition(!p.isSameDestination(sessionToken: deliveryToken,
      document: UUID(), fingerprint: proof))
    precondition(!p.mayRecoverCompleted(
      requestedToken: nil, activeToken: nil, deliveryToken: deliveryToken,
      deliveryEpoch: UUID(), currentDocument: nil, fingerprint: proof,
      recording: false, cancelled: false, hasSelection: false
    ))

    var envelope = AudioWaveformPeaks()
    precondition(envelope.waveform(count: 3) == [1, 1, 1])
    precondition(envelope.waveform(count: 0).isEmpty)
    envelope.append(0.25)
    envelope.append(-0.75)
    envelope.append(.nan)
    envelope.append(.infinity)
    precondition(envelope.waveform(count: 128) == [0.75, 0.25])
    precondition(envelope.waveform(count: 1) == [0.25])

    // Long capture stays bounded and preserves isolated peaks through merging.
    var long = AudioWaveformPeaks()
    for index in 0..<500_003 {
      long.append(index == 100_001 ? 1 : 0)
      precondition(long.retainedCount <= AudioWaveformPeaks.maximumBins)
    }
    let waveform = long.waveform(count: 128)
    precondition(waveform.count == 128)
    precondition(waveform.min() == 0 && waveform.max() == 1)
    precondition(waveform.allSatisfy { $0.isFinite && (0...1).contains($0) })
    print("Recording policies: stale/cancelled requests and bounded waveform PASS")
  }
}
