import Foundation

@main
struct DictationCaptureChecks {
  static func main() {
    func decision(
      healthy: Bool = true, owns: Bool = true,
      frames: Int = 0, elapsed: TimeInterval = 0
    ) -> DictationCapturePolicy.Confirmation {
      DictationCapturePolicy.confirmation(
        sessionHealthy: healthy, ownsCapture: owns,
        outputFrames: frames, elapsed: elapsed
      )
    }

    precondition(decision() == .waiting)
    precondition(decision(elapsed: 1.999) == .waiting)
    precondition(decision(elapsed: 2) == .timedOut)
    precondition(decision(elapsed: 10) == .timedOut)
    precondition(decision(elapsed: -.infinity) == .timedOut)
    precondition(decision(elapsed: .nan) == .timedOut)
    precondition(decision(frames: 1) == .confirmed)
    // Late scheduling must still accept frames that the audio tap delivered.
    precondition(decision(frames: 16_000, elapsed: 10) == .confirmed)
    precondition(decision(healthy: false, frames: 16_000) == .unavailable)
    precondition(decision(owns: false, frames: 16_000) == .unavailable)
    precondition(decision(healthy: false, owns: false, elapsed: 3) == .unavailable)
    precondition(DictationCapturePolicy.shouldDeferRequestedStop(
      confirmation: .waiting, awaitingConfirmation: true))
    precondition(!DictationCapturePolicy.shouldDeferRequestedStop(
      confirmation: .waiting, awaitingConfirmation: false))
    for state in [DictationCapturePolicy.Confirmation.confirmed, .unavailable, .timedOut] {
      precondition(!DictationCapturePolicy.shouldDeferRequestedStop(
        confirmation: state, awaitingConfirmation: true))
    }
    precondition(DictationCapturePolicy.isPendingStart(startedAt: 100, now: 101.999))
    precondition(!DictationCapturePolicy.isPendingStart(startedAt: 100, now: 102))
    precondition(!DictationCapturePolicy.isPendingStart(startedAt: 0, now: 1))
    precondition(!DictationCapturePolicy.isPendingStart(startedAt: 101, now: 100))
    precondition(!DictationCapturePolicy.isPendingStart(startedAt: .nan, now: 100))
    precondition(DictationCapturePolicy.canRejectUnacceptedRequest(
      activeToken: nil, recording: false, finalizing: false, ownsCapture: false))
    for active in 0..<4 {
      precondition(!DictationCapturePolicy.canRejectUnacceptedRequest(
        activeToken: active == 0 ? "accepted-request" : nil,
        recording: active == 1, finalizing: active == 2, ownsCapture: active == 3
      ))
    }
    print("Dictation capture confirmation: PASS")
  }
}
