
import UIKit

extension KeyboardViewController {

  static let processingCheckInterval: TimeInterval = 5
  static let processingHardTimeout: TimeInterval = 180

  /// Restore the absolute timeout after iOS suspends/recreates the keyboard.
  /// Progress start time is App Group state, not the lifetime of this view.
  func resumeProcessingTimeoutIfNeeded() {
    guard self.viewIfLoaded?.window != nil, !self.keyboardState.isRecording,
          self.keyboardState.isProcessing || self.keyboardState.isLLMProcessing else { return }
    let settings = SharedSettings()
    settings.synchronize()
    if let progress = self.keyboardState.voiceProcessingProgress,
       progress.isCurrent(for: settings.dictationSessionToken,
         cancelled: settings.dictationCancellationRequested) {
      self.processingStartTime = Date(timeIntervalSinceReferenceDate: progress.startedAt)
    } else if self.processingStartTime == nil {
      self.processingStartTime = Date()
    }
    // The host may answer a status ping with this same progress notification.
    // A current timer owns reconciliation; notifications must not rearm it.
    guard self.processingTimeoutTimer?.isValid != true else { return }
    self.startProcessingTimeout()
  }

  func pauseProcessingTimeout() {
    self.processingTimeoutTimer?.invalidate()
    self.processingTimeoutTimer = nil
    self.processingTimeoutGeneration = UUID()
  }

  func cancelProcessingTimeout() {
    self.pauseProcessingTimeout()
    self.processingStartTime = nil
    self.receivedPingDuringProcessing = false
  }

  func startProcessingTimeout() {
    if self.processingStartTime == nil {
      self.processingStartTime = Date()
    }
    guard self.viewIfLoaded?.window != nil else { return }
    self.receivedPingDuringProcessing = false
    self.pingMainAppForSessionStatus()

    self.processingTimeoutTimer?.invalidate()
    let generation = UUID()
    self.processingTimeoutGeneration = generation
    self.processingTimeoutTimer = Timer.scheduledTimer(
      withTimeInterval: Self.processingCheckInterval,
      repeats: false,
    ) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, self.processingTimeoutGeneration == generation else { return }
        self.processingTimeoutTimer = nil
        guard self.keyboardState.isProcessing || self.keyboardState.isLLMProcessing else { return }
        guard self.viewIfLoaded?.window != nil else { return }

        // Darwin notifications are wakeups, not durable delivery. Reconcile
        // the scoped outbox on every tick before deciding to wait or cancel.
        if self.keyboardState.isProcessing, self.insertTranscribedText() {
          self.finalizeProcessingPipeline()
        }
        if self.keyboardState.isLLMProcessing {
          self.checkForPendingLLMResult()
        }
        guard self.keyboardState.isProcessing || self.keyboardState.isLLMProcessing else {
          self.cancelProcessingTimeout()
          return
        }

        let elapsed = self.processingStartTime.map {
          Date().timeIntervalSince($0)
        } ?? 0

        let settings = SharedSettings()
        settings.synchronize()
        if self.receivedPingDuringProcessing || settings.dictationSessionToken != nil
            || self.keyboardState.isLLMProcessing {
          if elapsed < Self.processingHardTimeout {
            self.startProcessingTimeout()
          } else {
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

