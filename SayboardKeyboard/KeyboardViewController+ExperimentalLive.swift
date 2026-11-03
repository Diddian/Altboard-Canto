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

  func applyExperimentalLiveUpdate() {
    let settings = SharedSettings()
    settings.synchronize()
    guard settings.experimentalLiveDictationEnabled,
          self.keyboardState.isRecording,
          let update = ExperimentalLiveTranscription.read(),
          update.sessionToken == settings.dictationSessionToken,
          update.revision > self.liveTranscriptionRevision,
          self.liveTranscriptionBlockedToken != update.sessionToken,
          !update.text.isEmpty else { return }

    let proxy = self.textDocumentProxy
    if let owned = self.liveTranscriptionDocumentID {
      // Never follow the user to another host input field.
      guard owned == proxy.documentIdentifier else {
        self.liveTranscriptionBlockedToken = update.sessionToken
        self.abandonExperimentalLiveOwnership()
        return
      }
    } else {
      // A non-empty selection belongs to the user, not our dictated text.
      guard proxy.documentContextBeforeInput != nil,
            proxy.selectedText?.isEmpty ?? true else { return }
      self.liveTranscriptionDocumentID = proxy.documentIdentifier
      self.liveTranscriptionPrefix = DictationSpacing.separators(
        for: update.text,
        before: proxy.documentContextBeforeInput,
        after: proxy.documentContextAfterInput,
        isAddressField: proxy.keyboardType == .URL || proxy.keyboardType == .emailAddress
      ).leading
    }

    let marked = self.liveTranscriptionPrefix + update.text
    proxy.setMarkedText(marked, selectedRange: NSRange(location: (marked as NSString).length, length: 0))
    self.liveTranscriptionRevision = update.revision
    self.liveTranscriptionMarkedText = marked
  }

  /// Returns true if a live session owns the final result (even after focus
  /// loss). In that case inserting into a new input field would be unsafe.
  func completeExperimentalLiveText(_ final: String) -> Bool {
    guard let owned = self.liveTranscriptionDocumentID else { return false }
    defer { self.abandonExperimentalLiveOwnership() }
    guard owned == self.textDocumentProxy.documentIdentifier else {
      self.keyboardState.showFinalOutputPreview(final)
      return true
    }
    let output = self.liveTranscriptionPrefix + final
    self.textDocumentProxy.setMarkedText(
      output, selectedRange: NSRange(location: (output as NSString).length, length: 0)
    )
    self.textDocumentProxy.unmarkText()
    return true
  }

  func cancelExperimentalLiveText() {
    self.liveTranscriptionBlockedToken = nil
    defer { self.abandonExperimentalLiveOwnership() }
    guard let owned = self.liveTranscriptionDocumentID,
          owned == self.textDocumentProxy.documentIdentifier else { return }
    self.textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
    self.textDocumentProxy.unmarkText()
  }

  private func abandonExperimentalLiveOwnership() {
    self.liveTranscriptionDocumentID = nil
    self.liveTranscriptionMarkedText = ""
    self.liveTranscriptionPrefix = ""
    self.liveTranscriptionRevision = 0
  }
}
