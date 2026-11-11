
import UIKit

extension KeyboardViewController {

  static let processingCheckInterval: TimeInterval = 5
  static let processingHardTimeout: TimeInterval = 180

  /// Restore the absolute timeout after iOS suspends/recreates the keyboard.
  /// Progress start time is App Group state, not the lifetime of this view.
  func resumeProcessingTimeoutIfNeeded() {
    guard self.keyboardState.isProcessing, !self.keyboardState.isRecording else { return }
    let settings = SharedSettings()
    settings.synchronize()
    guard let progress = self.keyboardState.voiceProcessingProgress,
          progress.sessionToken == settings.dictationSessionToken else { return }
    self.processingStartTime = Date(timeIntervalSinceReferenceDate: progress.startedAt)
    FeatureDiagnostics.record(.speechFinalization, .queued,
      operationID: progress.sessionToken)
    self.startProcessingTimeout()
  }

  func cancelProcessingTimeout() {
    self.processingTimeoutTimer?.invalidate()
    self.processingTimeoutTimer = nil
    self.processingStartTime = nil
    self.receivedPingDuringProcessing = false
  }

  func startProcessingTimeout() {
    if self.processingStartTime == nil {
      self.processingStartTime = Date()
    }
    self.receivedPingDuringProcessing = false
    self.pingMainAppForSessionStatus()

    self.processingTimeoutTimer?.invalidate()
    self.processingTimeoutTimer = Timer.scheduledTimer(
      withTimeInterval: Self.processingCheckInterval,
      repeats: false,
    ) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, self.keyboardState.isProcessing || self.keyboardState.isLLMProcessing else { return }

        let elapsed = self.processingStartTime.map {
          Date().timeIntervalSince($0)
        } ?? 0

        let settings = SharedSettings()
        settings.synchronize()
        if self.receivedPingDuringProcessing || settings.dictationSessionToken != nil
            || self.keyboardState.isLLMProcessing {
          if elapsed < Self.processingHardTimeout {
            if self.keyboardState.isLLMProcessing {
              self.checkForPendingLLMResult()
            }
            if !self.keyboardState.isProcessing, !self.keyboardState.isLLMProcessing {
              self.cancelProcessingTimeout()
              return
            }
            self.startProcessingTimeout()
          } else {
            self.insertTranscribedText()
            self.checkForPendingLLMResult()
            // The previous implementation reset only the keyboard flags,
            // leaving the host worker and session token alive indefinitely.
            FeatureDiagnostics.record(.speechFinalization, .failed,
              operationID: self.dictationRequestToken)
            if self.keyboardState.isProcessing {
              self.cancelDictationViaDarwin()
            }
            self.abandonPendingLLMRequest()
            self.resetProcessingState()
          }
        } else {
          self.insertTranscribedText()
          self.checkForPendingLLMResult()
          self.resetProcessingState()
        }
      }
    }
  }

  func resetProcessingState() {
    self.cancelProcessingTimeout()
    self.keyboardState.stopLevelPolling()
    self.keyboardState.isProcessing = false
    self.keyboardState.voiceProcessingProgress = nil
    self.keyboardState.isRecording = false
    self.keyboardState.isStartingRecording = false
    self.keyboardState.isSessionActive = false
    self.keyboardState.isLLMProcessing = false
    if !self.isPerformingHistoryNavigation {
      self.keyboardState.clearLLMHistory()
    }
    // Request reconciliation; the extension cannot stop the host audio engine.
    self.pingMainAppForSessionStatus()
  }
}

