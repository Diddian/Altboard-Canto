import Foundation

@MainActor
final class PingValidator {

  func startIfNeeded(for keyboardState: KeyboardState) {
    guard keyboardState.isSessionActive else { return }
    self.responseReceived = false
    self.timer?.invalidate()
    self.timer = Timer.scheduledTimer(
      withTimeInterval: Self.timeout,
      repeats: false,
    ) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, !self.responseReceived else { return }
        guard keyboardState.isSessionActive else { return }
        let settings = SharedSettings()
        settings.synchronize()
        if DictationRequestPolicy.hasRecentAudioHeartbeat(
          settings.mainAppHeartbeat, now: CFAbsoluteTimeGetCurrent()
        ) {
          // A delayed Darwin reply is not proof that the main app is dead.
          DiagnosticLog.write("keyboard: session ping delayed; live audio state retained")
          return
        }
        // Recover a stale keyboard view locally. Only the containing app
        // owns and may clear the persisted AVAudioSession lifecycle flags.
        keyboardState.isSessionActive = false
        keyboardState.isRecording = false
        keyboardState.isStartingRecording = false
        keyboardState.stopLevelPolling()
        DiagnosticLog.write("keyboard: no recent audio heartbeat; local state reset")
      }
    }
  }

  func cancel() {
    self.responseReceived = true
    self.timer?.invalidate()
    self.timer = nil
  }

  private static let timeout: TimeInterval = 1

  private var timer: Timer?
  private var responseReceived = false
}
