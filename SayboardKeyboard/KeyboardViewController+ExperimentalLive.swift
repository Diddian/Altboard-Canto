import UIKit

/// Host-owned live words are appended as each offline Qwen chunk finishes.
/// No raw host text is stored. A session token, document ID and short suffix
/// anchor prevent updates to an unrelated field after cursor/focus changes.
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
          (self.keyboardState.isRecording || settings.isRecording),
          let update = ExperimentalLiveTranscription.read(),
          update.sessionToken == settings.dictationSessionToken,
          update.revision > self.liveTranscriptionRevision,
          self.liveTranscriptionBlockedToken != update.sessionToken,
          !update.text.isEmpty else { return }

    let proxy = self.textDocumentProxy
    if let owned = self.liveTranscriptionDocumentID {
      guard owned == proxy.documentIdentifier else {
        self.blockExperimentalLiveChanges(token: update.sessionToken)
        return
      }
      guard update.text.hasPrefix(self.liveTranscriptionCommittedRaw) else {
        self.blockExperimentalLiveChanges(token: update.sessionToken)
        return
      }
      let added = String(update.text.dropFirst(self.liveTranscriptionCommittedRaw.count))
      if added.isEmpty {
        self.liveTranscriptionRevision = update.revision
        return
      }
      // UITextDocumentProxy exposes only bounded context in many hosts.
      // A short exact suffix plus document ID is enough for append-only input.
      let anchor = String(self.liveTranscriptionMarkedText.suffix(24))
      guard !anchor.isEmpty,
            proxy.documentContextBeforeInput?.hasSuffix(anchor) == true,
            proxy.selectedText?.isEmpty ?? true else {
        self.blockExperimentalLiveChanges(token: update.sessionToken)
        return
      }
      proxy.insertText(added)
      self.liveTranscriptionCommittedRaw = update.text
      self.liveTranscriptionMarkedText += added
      self.liveTranscriptionRevision = update.revision
      return
    }

    // An EMPTY host field legitimately returns nil contextBeforeInput.
    // Do not require a non-nil context to begin live insertion.
    guard proxy.selectedText?.isEmpty ?? true else { return }
    let before = proxy.documentContextBeforeInput
    let prefix = DictationSpacing.separators(
      for: update.text, before: before, after: proxy.documentContextAfterInput,
      isAddressField: proxy.keyboardType == .URL || proxy.keyboardType == .emailAddress
    ).leading
    proxy.insertText(prefix + update.text)
    self.liveTranscriptionDocumentID = proxy.documentIdentifier
    self.liveTranscriptionPrefix = prefix
    self.liveTranscriptionCommittedRaw = update.text
    self.liveTranscriptionMarkedText = prefix + update.text
    self.liveTranscriptionRevision = update.revision
  }

  /// Never append the same final transcript twice. Replace live words only
  /// when the whole owned prefix is visible and verified; otherwise append a
  /// confirmed missing suffix, or expose the final result for manual review.
  func completeExperimentalLiveText(_ final: String) -> Bool {
    guard let owned = self.liveTranscriptionDocumentID else { return false }
    defer { self.abandonExperimentalLiveOwnership() }
    guard owned == self.textDocumentProxy.documentIdentifier else {
      self.keyboardState.showFinalOutputPreview(final)
      return true
    }
    let proxy = self.textDocumentProxy
    if final == self.liveTranscriptionCommittedRaw { return true }
    let anchor = String(self.liveTranscriptionMarkedText.suffix(24))
    guard !anchor.isEmpty,
          proxy.documentContextBeforeInput?.hasSuffix(anchor) == true,
          proxy.selectedText?.isEmpty ?? true else {
      self.keyboardState.showFinalOutputPreview(final)
      return true
    }
    if final.hasPrefix(self.liveTranscriptionCommittedRaw) {
      proxy.insertText(String(final.dropFirst(self.liveTranscriptionCommittedRaw.count)))
    } else if proxy.documentContextBeforeInput?.hasSuffix(self.liveTranscriptionMarkedText) == true {
      // Full context is available, so a bounded verified replacement is safe.
      for _ in self.liveTranscriptionMarkedText { proxy.deleteBackward() }
      proxy.insertText(self.liveTranscriptionPrefix + final)
    } else {
      // Context truncated: do not erase unrelated material to correct a word.
      self.keyboardState.showFinalOutputPreview(final)
    }
    return true
  }

  func cancelExperimentalLiveText() {
    self.liveTranscriptionBlockedToken = nil
    defer { self.abandonExperimentalLiveOwnership() }
    guard let owned = self.liveTranscriptionDocumentID,
          owned == self.textDocumentProxy.documentIdentifier,
          self.textDocumentProxy.documentContextBeforeInput?
            .hasSuffix(self.liveTranscriptionMarkedText) == true else { return }
    for _ in self.liveTranscriptionMarkedText { self.textDocumentProxy.deleteBackward() }
  }

  private func blockExperimentalLiveChanges(token: String) {
    self.liveTranscriptionBlockedToken = token
    self.abandonExperimentalLiveOwnership()
  }

  private func abandonExperimentalLiveOwnership() {
    self.liveTranscriptionDocumentID = nil
    self.liveTranscriptionMarkedText = ""
    self.liveTranscriptionCommittedRaw = ""
    self.liveTranscriptionPrefix = ""
    self.liveTranscriptionRevision = 0
  }
}
