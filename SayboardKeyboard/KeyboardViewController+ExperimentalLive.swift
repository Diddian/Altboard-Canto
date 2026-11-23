import UIKit

extension KeyboardViewController {
  static var experimentalLiveObserver: DarwinNotificationObserver?

  func setupExperimentalLiveObserver() {
    Self.experimentalLiveObserver?.stopObserving()
    Self.experimentalLiveObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.experimentalLiveTranscriptUpdated
    ) {
      DispatchQueue.main.async {
        Self.activeInstance?.applyExperimentalLiveUpdate()
      }
    }
  }

  // Live words are a keyboard preview. The final result is the only host write.
  func applyExperimentalLiveUpdate() {
    let settings = SharedSettings()
    settings.synchronize()
    guard self.dictationStartupVisible, self.viewIfLoaded?.window != nil,
          settings.experimentalLiveDictationEnabled, settings.isRecording,
          !settings.dictationCancellationRequested,
          let update = ExperimentalLiveTranscription.read(),
          update.sessionToken == self.dictationRequestToken,
          update.sessionToken == settings.dictationSessionToken,
          update.sessionToken != TranscriptionBridge.cancellationToken(),
          update.revision > self.liveTranscriptionRevision,
          !update.text.isEmpty else { return }
    self.liveTranscriptionRevision = update.revision
    self.keyboardState.liveSourcePreview = String(update.text.suffix(240))
  }
}
