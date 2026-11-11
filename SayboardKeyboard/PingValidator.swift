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
        // A slow or missed Darwin reply is not permission to end the
        // main app's AVAudioSession. Its owner emits authoritative lifecycle
        // notifications; a keyboard must never clear persisted audio state.
        DiagnosticLog.write("keyboard: session status ping timed out; state preserved")
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
