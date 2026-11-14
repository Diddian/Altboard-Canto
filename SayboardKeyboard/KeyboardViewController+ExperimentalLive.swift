import UIKit

/// Host-owned live words are appended as each offline Qwen chunk finishes.
/// No raw host text is stored. A session token, document ID and short suffix
/// anchor prevent updates to an unrelated field after cursor/focus changes.
enum LiveFinalDeliveryResult {
  case notApplicable, inserted, review
}

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
    // Keep recognized words live while the selected output is processed.
    // The final bridge only replaces text still owned in the same host field.
    guard settings.experimentalLiveDictationEnabled,
          (self.keyboardState.isRecording || settings.isRecording),
          let update = ExperimentalLiveTranscription.read(),
          update.sessionToken == self.dictationRequestToken,
          update.sessionToken == settings.dictationSessionToken,
          update.revision > self.liveTranscriptionRevision,
          !update.text.isEmpty else { return }

    // Display source-language speech even after iOS recreates the keyboard.
    // A blocked destination must never suppress read-only preview text.
    self.keyboardState.liveSourcePreview = String(update.text.suffix(240))
    guard self.liveTranscriptionBlockedToken != update.sessionToken,
          Self.blockedLiveSessionToken != update.sessionToken else { return }
    guard LiveDeliveryPolicy.accepts(
      token: update.sessionToken,
      requestToken: self.dictationRequestToken,
      currentToken: settings.dictationSessionToken,
      revision: update.revision,
      lastRevision: self.liveTranscriptionRevision,
      updatedAt: update.updatedAt,
      now: Date().timeIntervalSinceReferenceDate,
      destinationEpoch: settings.dictationDestinationEpoch,
      currentEpoch: self.keyboardState.documentEpoch
    ) else { return }
    let proxy = self.textDocumentProxy
    guard let document = self.availableDocumentIdentifier() else {
      // Never insert live text when UIKit cannot confirm the destination field.
      self.blockExperimentalLiveChanges(token: update.sessionToken)
      return
    }
    if let owned = self.liveTranscriptionDocumentID {
      let anchor = String(self.liveTranscriptionMarkedText.suffix(24))
      guard self.liveTranscriptionOwnerToken == update.sessionToken,
            LiveDeliveryPolicy.matchesField(
              ownedDocument: owned, currentDocument: document,
              ownedEpoch: self.liveTranscriptionDocumentEpoch,
              currentEpoch: self.keyboardState.documentEpoch,
              anchor: anchor,
              before: proxy.documentContextBeforeInput,
              expectedAfter: self.liveTranscriptionContextAfter,
              after: proxy.documentContextAfterInput,
              selectedText: proxy.selectedText
            ) else {
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
    guard ExperimentalLiveTranscription.claimHostInsertion(for: update.sessionToken) else {
      FeatureDiagnostics.record(.liveDictation, .fallback, operationID: update.sessionToken)
      self.blockExperimentalLiveChanges(token: update.sessionToken)
      return
    }
    proxy.insertText(prefix + update.text)
    LiveDictationLatency.mark(.firstHostInsert, token: update.sessionToken)
    FeatureDiagnostics.record(.liveDictation, .firstHostInsert,
      durationMs: LiveDictationLatency.elapsedMs(.firstHostInsert),
      operationID: update.sessionToken)
    self.liveTranscriptionDocumentID = document
    self.liveTranscriptionDocumentEpoch = self.keyboardState.documentEpoch
    self.liveTranscriptionOwnerToken = update.sessionToken
    self.liveTranscriptionContextAfter = proxy.documentContextAfterInput
    self.liveTranscriptionPrefix = prefix
    self.liveTranscriptionCommittedRaw = update.text
    self.liveTranscriptionMarkedText = prefix + update.text
    self.liveTranscriptionRevision = update.revision
  }

  /// Never append the same final transcript twice. Replace live words only
  /// when the whole owned prefix is visible and verified; otherwise append a
  /// confirmed missing suffix, or expose the final result for manual review.
  func completeExperimentalLiveText(
    _ delivery: DictationDelivery, cancellationRequested: Bool
  ) -> LiveFinalDeliveryResult {
    guard self.liveTranscriptionDocumentID != nil else { return .notApplicable }
    defer { self.abandonExperimentalLiveOwnership() }
    let final = delivery.text
    let proxy = self.textDocumentProxy
    // The host clears SharedSettings.dictationSessionToken before notifying
    // the keyboard. Validate the immutable delivery, not the cleared flag.
    guard LiveFinalDeliveryPolicy.mayReconcile(
      delivery: delivery, requestToken: self.dictationRequestToken,
      ownerToken: self.liveTranscriptionOwnerToken,
      currentEpoch: self.keyboardState.documentEpoch,
      ownerEpoch: self.liveTranscriptionDocumentEpoch,
      requestDocument: self.dictationDocumentID,
      ownedDocument: self.liveTranscriptionDocumentID,
      currentDocument: self.availableDocumentIdentifier(),
      anchor: String(self.liveTranscriptionMarkedText.suffix(24)),
      before: proxy.documentContextBeforeInput,
      expectedAfter: self.liveTranscriptionContextAfter,
      after: proxy.documentContextAfterInput,
      selectedText: proxy.selectedText,
      blockedToken: self.liveTranscriptionBlockedToken,
      blockedKeyboardToken: Self.blockedLiveSessionToken,
      cancelled: cancellationRequested
    ) else {
      FeatureDiagnostics.record(.bridge, .fallback, operationID: delivery.sessionToken)
      return .review
    }
    let plan = LiveFinalReconciliation.plan(
      partial: self.liveTranscriptionCommittedRaw, final: final,
      marked: self.liveTranscriptionMarkedText,
      prefix: self.liveTranscriptionPrefix,
      before: proxy.documentContextBeforeInput
    )
    switch plan {
    case .unchanged:
      break
    case .append(let suffix):
      proxy.insertText(suffix)
    case .replace(let replacement):
      for _ in self.liveTranscriptionMarkedText { proxy.deleteBackward() }
      proxy.insertText(replacement)
    case .review:
      // A truncated host context must never trigger destructive correction.
      return .review
    }
    return .inserted
  }

  func cancelExperimentalLiveText() {
    // A delayed partial notification must not reinsert cancelled speech.
    self.liveTranscriptionBlockedToken =
      self.liveTranscriptionOwnerToken ?? self.dictationRequestToken
    defer { self.abandonExperimentalLiveOwnership() }
    let proxy = self.textDocumentProxy
    guard let owned = self.liveTranscriptionDocumentID,
          self.liveTranscriptionOwnerToken == self.dictationRequestToken,
          LiveDeliveryPolicy.matchesField(
            ownedDocument: owned, currentDocument: self.availableDocumentIdentifier(),
            ownedEpoch: self.liveTranscriptionDocumentEpoch,
            currentEpoch: self.keyboardState.documentEpoch,
            anchor: self.liveTranscriptionMarkedText,
            before: proxy.documentContextBeforeInput,
            expectedAfter: self.liveTranscriptionContextAfter,
            after: proxy.documentContextAfterInput,
            selectedText: proxy.selectedText
          ) else { return }
    for _ in self.liveTranscriptionMarkedText { proxy.deleteBackward() }
  }

  private func blockExperimentalLiveChanges(token: String) {
    self.liveTranscriptionBlockedToken = token
    self.abandonExperimentalLiveOwnership()
  }

  func abandonExperimentalLiveOwnership() {
    self.liveTranscriptionDocumentID = nil
    self.liveTranscriptionDocumentEpoch = nil
    self.liveTranscriptionOwnerToken = nil
    self.liveTranscriptionContextAfter = nil
    self.liveTranscriptionMarkedText = ""
    self.liveTranscriptionCommittedRaw = ""
    self.liveTranscriptionPrefix = ""
    self.liveTranscriptionRevision = 0
  }
}

