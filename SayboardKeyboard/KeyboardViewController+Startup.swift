import UIKit

extension KeyboardViewController {
  func beginDictationStartup(token: String) {
    let settings = SharedSettings()
    if DictationStartupPolicy.begin(
      token: token, now: CFAbsoluteTimeGetCurrent(), defaults: settings.defaults
    ) {
      settings.synchronize()
      FeatureDiagnostics.record(.speech, .queued, operationID: token, phase: .accepted)
    }
    self.resumeDictationStartupIfNeeded()
  }

  func pauseDictationStartup() {
    self.dictationStartupTimer?.invalidate()
    self.dictationStartupTimer = nil
    self.dictationStartupGeneration = UUID()
  }

  func finishDictationStartup(for token: String?) {
    self.pauseDictationStartup()
    let settings = SharedSettings()
    DictationStartupPolicy.clear(matching: token, defaults: settings.defaults)
    settings.synchronize()
  }

  func resumeDictationStartupIfNeeded() {
    guard self.dictationStartupVisible, self.viewIfLoaded?.window != nil,
          self.dictationStartupTimer?.isValid != true else { return }
    let settings = SharedSettings()
    settings.synchronize()
    guard let request = DictationStartupPolicy.request(
      for: self.dictationRequestToken, defaults: settings.defaults
    ) else { return }
    self.reconcileDictationStartup(request)
  }

  private func reconcileDictationStartup(_ request: DictationStartupPolicy.Request) {
    guard self.dictationRequestToken == request.token else { return }
    let settings = SharedSettings()
    settings.synchronize()
    let visible = self.dictationStartupVisible && self.viewIfLoaded?.window != nil
    let progress = TranscriptionBridge.readVoiceProgress()?.isCurrent(
      for: request.token, cancelled: settings.dictationCancellationRequested
    ) == true
    let now = CFAbsoluteTimeGetCurrent()
    let action = DictationStartupPolicy.decision(
      request: request, currentToken: settings.dictationSessionToken,
      cancelled: settings.dictationCancellationRequested,
      visible: visible, captureAcknowledged: self.keyboardState.isRecording,
      recordedFrames: settings.isRecording,
      recentAudioHeartbeat: DictationRequestPolicy.hasRecentAudioHeartbeat(
        settings.mainAppHeartbeat, now: now
      ),
      currentProgress: progress,
      stopRequested: TranscriptionBridge.stopToken() == request.token,
      modelLoading: settings.isModelLoading, now: now
    )
    // A final result can arrive while this view is suspended. Reuse the
    // destination-checked insertion path before considering cancellation.
    // Avoid scanning the outbox on every startup tick.
    if visible, action != .waiting, action != .processing,
       settings.dictationSessionToken == nil || settings.dictationSessionToken == request.token,
       TranscriptionBridge.readDelivery(matching: request.token, allowAnyDestination: true) != nil,
       self.insertTranscribedText() {
      self.finishDictationStartup(for: request.token)
      self.finalizeProcessingPipeline()
      return
    }
    switch action {
    case .finished:
      self.finishDictationStartup(for: request.token)
      self.keyboardState.isStartingRecording = false
    case .paused:
      self.pauseDictationStartup()
    case .processing:
      self.finishDictationStartup(for: request.token)
      self.keyboardState.isStartingRecording = false
      self.keyboardState.isRecording = false
      self.keyboardState.isProcessing = true
      self.keyboardState.syncVoiceProcessingProgress()
      self.resumeProcessingTimeoutIfNeeded()
    case .finishCapturedSpeech:
      FeatureDiagnostics.record(.speech, .fallback,
        failureReason: .warmStartUnacknowledged, operationID: request.token)
      self.stopDictationViaDarwin()
    case .expired:
      FeatureDiagnostics.record(.speech, .failed,
        durationMs: Int(max(0, min(180, now - request.startedAt)) * 1_000),
        failureReason: .audioCaptureUnconfirmed, operationID: request.token,
        phase: .failed)
      self.cancelDictationViaDarwin()
      self.keyboardState.dictationOutcome = .activationFailed
    case .waiting:
      self.keyboardState.isStartingRecording = true
      self.pingMainAppForSessionStatus()
      self.scheduleDictationStartupCheck(request)
    }
  }

  private func scheduleDictationStartupCheck(_ request: DictationStartupPolicy.Request) {
    self.pauseDictationStartup()
    let generation = self.dictationStartupGeneration
    self.dictationStartupTimer = Timer.scheduledTimer(
      withTimeInterval: 1, repeats: false
    ) { [weak self] _ in
      DispatchQueue.main.async { [weak self] in
        guard let self, self.dictationStartupGeneration == generation else { return }
        self.dictationStartupTimer = nil
        self.reconcileDictationStartup(request)
      }
    }
  }
}
