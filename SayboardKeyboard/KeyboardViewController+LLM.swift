
import NaturalLanguage

import UIKit

extension KeyboardViewController {

  func setupLLMObservers() {
    Self.llmStartedObserver?.stopObserving()
    Self.llmCompleteObserver?.stopObserving()
    Self.llmFailedObserver?.stopObserving()
    Self.llmStartedObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.llmProcessingStarted
    ) {
      DispatchQueue.main.async {
        guard let vc = Self.activeInstance else { return }
        vc.syncLLMRequestStatus()
      }
    }

    Self.llmCompleteObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.llmProcessingComplete
    ) {
      DispatchQueue.main.async {
        guard let vc = Self.activeInstance else { return }
        vc.insertLLMResult()
      }
    }

    Self.llmFailedObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.llmProcessingFailed
    ) {
      DispatchQueue.main.async {
        guard let vc = Self.activeInstance else { return }
        vc.syncLLMRequestStatus()
      }
    }
  }

  @discardableResult
  func autoApplyLLMIfNeeded(directText: String? = nil) -> Bool {
    // Voice transcription has already been processed by the main app.
    // Never apply a second, unrelated automatic LLM action.
    guard !SharedSettings().lastVoiceOutputProcessed else { return false }
    guard self.keyboardState.llmEnabled else { return false }
    guard self.keyboardState.hasUsableLLMModel else { return false }
    guard !self.keyboardState.isDictationLocked else { return false }
    guard !self.keyboardState.isLLMProcessing else { return false }

    let selection = self.keyboardState.defaultLLMActionSelection
    guard selection.isSet else { return false }

    let resolved = selection.resolve(
      defaultAction: .rewrite,
      customPrompts: self.keyboardState.llmCustomPrompts,
      disabledActions: self.keyboardState.disabledLLMActions,
    )

    guard let resolved else {
      self.keyboardState.defaultLLMActionSelection = .none
      SharedSettings().defaultLLMActionSelection = .none
      return false
    }

    if resolved.action == .translate {
      let settings = SharedSettings()
      guard settings.voiceOutputTarget != .original,
            settings.voiceOutputTarget.targetInstruction(customLanguage: settings.voiceCustomLanguage) != nil
      else { return false }
    }
    self.requestLLMProcessing(action: resolved.action, customPromptId: resolved.customPromptId, directText: directText)
    return true
  }

  func requestLLMProcessing(
    action: LLMAction, customPromptId: UUID?,
    directText: String? = nil, clipboardOnly: Bool = false
  ) {
    guard !self.keyboardState.isLLMProcessing else {
      return
    }

    let target = SharedSettings().voiceOutputTarget
    let customLanguage = SharedSettings().voiceCustomLanguage
    if action == .translate,
       (target == .original || target.targetInstruction(customLanguage: customLanguage) == nil) {
      self.keyboardState.llmError = .translationTargetRequired
      return
    }
    let inputText: String
    self.llmSelectedText = nil
    self.llmDirectSelectedText = nil
    self.llmRequestID = nil
    self.llmDocumentIdentifier = nil
    self.llmSelectionContextBefore = nil
    self.llmSelectionContextAfter = nil
    self.llmClipboardOnly = clipboardOnly
    self.pendingManualLLMAction = nil
    self.keyboardState.llmError = nil
    if let directText {
      inputText = directText
      self.llmOriginalText = ""
      self.pendingAutoActionText = clipboardOnly ? nil : directText
      if !clipboardOnly {
        let proxy = self.textDocumentProxy
        self.llmDocumentIdentifier = self.availableDocumentIdentifier()
        self.llmSelectionContextBefore = proxy.documentContextBeforeInput
        self.llmSelectionContextAfter = proxy.documentContextAfterInput
        self.llmDirectSelectedText = proxy.selectedText
      }
    } else {
      // The proxy can expose selected text, not arbitrary host-field contents.
      guard let selected = self.textDocumentProxy.selectedText,
            !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        self.keyboardState.llmError = .selectText
        self.pendingManualLLMAction = (action, customPromptId)
        return
      }
      inputText = selected
      self.llmSelectedText = selected
      self.llmDocumentIdentifier = self.availableDocumentIdentifier()
      self.llmSelectionContextBefore = self.textDocumentProxy.documentContextBeforeInput
      self.llmSelectionContextAfter = self.textDocumentProxy.documentContextAfterInput
      self.llmOriginalText = ""
      self.pendingAutoActionText = nil
    }

    self.keyboardState.isLLMProcessing = true

    if self.keyboardState.llmHistoryDocumentIdentifier != self.llmDocumentIdentifier
        || self.keyboardState.llmHistoryEpoch != self.keyboardState.documentEpoch {
      self.keyboardState.clearLLMHistory()
    }
    if self.keyboardState.llmTextHistory.isEmpty {
      self.keyboardState.llmTextHistory = [inputText]
      self.keyboardState.llmHistoryIndex = 0
    } else {
      let idx = self.keyboardState.llmHistoryIndex
      self.keyboardState.llmTextHistory = Array(self.keyboardState.llmTextHistory.prefix(idx + 1))
    }
    self.keyboardState.llmHistoryDocumentIdentifier = self.llmDocumentIdentifier
    self.keyboardState.llmHistoryEpoch = self.llmDocumentIdentifier == nil
      ? nil : self.keyboardState.documentEpoch

    let language = Self.detectLanguage(from: inputText)

    let request = LLMRequest(
      text: inputText,
      action: action,
      customPromptId: customPromptId,
      language: language,
      translationTarget: action == .translate ? target.rawValue : nil,
      customTranslationLanguage: action == .translate ? customLanguage : nil,
    )
    self.llmRequestID = request.requestID
    // The bridge checks for previous requests/results under a cross-process
    // lock. Never delete a different keyboard's unfinished output.
    guard LLMBridge.writeRequest(request) else {
      let occupied = LLMBridge.readRequest() != nil || LLMBridge.hasResult()
      self.keyboardState.llmError = .storageUnavailable
      self.insertPendingAutoActionFallback()
      self.keyboardState.showFinalOutputPreview(occupied
        ? "Another text action is pending. No previous result was removed."
        : "Text storage unavailable. Original text retained.")
      self.keyboardState.clearLLMHistory()
      self.finishLLMInsertion()
      return
    }
    self.startProcessingTimeout()
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.requestLLMProcessing)
    DiagnosticLog.write("llm/kb: requested \(action.rawValue), text=\(inputText.count) chars")
  }

  func requestLLMClipboardProcessing() {
    guard let pending = self.pendingManualLLMAction else {
      self.keyboardState.llmError = .selectText
      return
    }
    // Explicit user action: iOS may display a paste permission prompt.
    guard self.keyboardState.hasFullAccess,
          let copied = UIPasteboard.general.string,
          !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      self.keyboardState.llmError = .clipboardUnavailable
      return
    }
    self.requestLLMProcessing(
      action: pending.action, customPromptId: pending.customPromptId,
      directText: copied, clipboardOnly: true
    )
  }

  func checkForPendingLLMResult() {
    if self.syncLLMRequestStatus() { return }
    guard LLMBridge.hasResult() else { return }
    guard let result = LLMBridge.readResult(matching: self.llmRequestID),
          !result.isEmpty else {
      FeatureDiagnostics.record(.bridge, .rejected)
      // A response owned by a previous keyboard/request must never enter
      // the currently focused document.
      return
    }
    self.insertLLMResult()
  }

  @discardableResult
  func syncLLMRequestStatus() -> Bool {
    guard let id = self.llmRequestID,
          let status = LLMBridge.readStatus(matching: id) else { return false }
    switch status.phase {
    case .busy, .failed, .rejected, .cancelled:
      self.insertPendingAutoActionFallback()
      self.keyboardState.showFinalOutputPreview(
        status.phase == .busy ? "Text model busy. Try again after the current task."
          : "Text action unavailable. Your original text is unchanged."
      )
      self.finishLLMInsertion()
      return true
    case .requested, .accepted, .running:
      self.keyboardState.isLLMProcessing = true
    case .completed:
      break
    }
    return false
  }

  func abandonPendingLLMRequest() {
    guard let id = self.llmRequestID else { return }
    LLMBridge.writeStatus(.cancelled, requestID: id)
    self.insertPendingAutoActionFallback()
    self.keyboardState.showFinalOutputPreview("Text action timed out. Original text retained.")
    self.finishLLMInsertion()
  }

  private static func detectLanguage(from text: String) -> String? {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    guard let dominant = recognizer.dominantLanguage else { return nil }
    return dominant.rawValue
  }

  private func currentLLMFieldMatches() -> Bool {
    guard let document = self.llmDocumentIdentifier,
          let current = self.availableDocumentIdentifier() else { return false }
    let proxy = self.textDocumentProxy
    return current == document
      && proxy.documentContextBeforeInput == self.llmSelectionContextBefore
      && proxy.documentContextAfterInput == self.llmSelectionContextAfter
      && proxy.selectedText == self.llmDirectSelectedText
  }

  private func insertPendingAutoActionFallback() {
    guard let fallbackText = self.pendingAutoActionText else { return }
    if self.currentLLMFieldMatches() {
      self.keyboardState.llmHistorySuffix = self.insertSpacedText(fallbackText).trailing
    } else {
      UIPasteboard.general.string = fallbackText
      self.keyboardState.showFinalOutputPreview("Input changed. Dictation copied.")
    }
    self.pendingAutoActionText = nil
  }

  private func insertLLMResult() {
    guard let result = LLMBridge.readResult(matching: self.llmRequestID),
          !result.isEmpty else {
      if LLMBridge.hasResult() {
        // A stale response must not end an unrelated, still-active action.
        return
      }
      FeatureDiagnostics.record(.bridge, .unavailable)
      DiagnosticLog.write("llm/kb: notified complete but bridge held no result")
      self.insertPendingAutoActionFallback()
      self.keyboardState.isLLMProcessing = false
      return
    }
    DiagnosticLog.write("llm/kb: inserting \(result.count) chars")

    if self.llmClipboardOnly {
      FeatureDiagnostics.record(.bridge, .fallback)
      UIPasteboard.general.string = result
      self.keyboardState.showFinalOutputPreview("Rewrite copied. Paste to replace.")
      self.keyboardState.clearLLMHistory()
      self.finishLLMInsertion()
      return
    }
    if let originalSelection = self.llmSelectedText {
      // Never overwrite a changed selection after asynchronous inference.
      // Both IDs must exist. nil == nil must never authorize replacement.
      let matches = self.llmDocumentIdentifier != nil
        && self.availableDocumentIdentifier() == self.llmDocumentIdentifier
        && textDocumentProxy.selectedText == originalSelection
        && textDocumentProxy.documentContextBeforeInput == self.llmSelectionContextBefore
        && textDocumentProxy.documentContextAfterInput == self.llmSelectionContextAfter
      if matches {
        textDocumentProxy.insertText(result)
        FeatureDiagnostics.record(.bridge, .completed)
        self.keyboardState.showFinalOutputPreview("Selected text rewritten")
      } else {
        FeatureDiagnostics.record(.bridge, .fallback)
        UIPasteboard.general.string = result
        self.keyboardState.showFinalOutputPreview("Selection changed. Rewrite copied.")
      }
      self.keyboardState.clearLLMHistory()
      self.finishLLMInsertion()
      return
    }

    guard self.currentLLMFieldMatches() else {
      FeatureDiagnostics.record(.bridge, .fallback)
      UIPasteboard.general.string = result
      self.keyboardState.showFinalOutputPreview("Input changed. Rewrite copied.")
      self.keyboardState.clearLLMHistory()
      self.finishLLMInsertion()
      return
    }

    let currentBeforeText = textDocumentProxy.documentContextBeforeInput ?? ""
    let expected = self.llmOriginalText
    guard expected.isEmpty || currentBeforeText == expected else {
      FeatureDiagnostics.record(.bridge, .rejected)
      DiagnosticLog.write("llm/kb: document changed under the request, refusing to replace")
      self.keyboardState.llmError = .noTextBeforeCursor
      self.finishLLMInsertion()
      return
    }

    for _ in 0 ..< expected.count {
      textDocumentProxy.deleteBackward()
    }

    if expected.isEmpty {
      self.keyboardState.llmHistorySuffix = self.insertSpacedText(result).trailing
    } else {
      let suffix = self.keyboardState.llmHistorySuffix
      let kept = expected.hasSuffix(suffix) ? suffix : ""
      textDocumentProxy.insertText(result + kept)
      self.keyboardState.llmHistorySuffix = kept
    }
    if self.pendingAutoActionText != nil {
      self.keyboardState.showFinalOutputPreview(result)
    }

    FeatureDiagnostics.record(.bridge, .completed)
    self.keyboardState.llmTextHistory.append(result)
    self.keyboardState.llmHistoryIndex = self.keyboardState.llmTextHistory.count - 1

    self.finishLLMInsertion()
  }

  private func finishLLMInsertion() {
    if let id = self.llmRequestID {
      LLMBridge.clearResult(matching: id)
      LLMBridge.clearRequest(matching: id)
      LLMBridge.clearStatus(matching: id)
    }
    if !self.keyboardState.isProcessing { self.cancelProcessingTimeout() }
    self.keyboardState.isLLMProcessing = false
    self.pendingAutoActionText = nil
    self.llmOriginalText = ""
    self.llmSelectedText = nil
    self.llmDirectSelectedText = nil
    self.llmRequestID = nil
    self.llmDocumentIdentifier = nil
    self.llmSelectionContextBefore = nil
    self.llmSelectionContextAfter = nil
    self.llmClipboardOnly = false
    self.pendingManualLLMAction = nil
  }

  private func navigateLLMHistory(to targetIndex: Int) {
    let currentIndex = self.keyboardState.llmHistoryIndex
    let history = self.keyboardState.llmTextHistory
    guard let origin = self.keyboardState.llmHistoryDocumentIdentifier,
          self.availableDocumentIdentifier() == origin,
          self.keyboardState.llmHistoryEpoch == self.keyboardState.documentEpoch,
          history.indices.contains(currentIndex), history.indices.contains(targetIndex),
          (self.textDocumentProxy.selectedText?.isEmpty ?? true) else {
      self.keyboardState.clearLLMHistory()
      FeatureDiagnostics.record(.aiActions, .rejected, failureReason: .destinationChanged)
      return
    }
    let suffix = self.keyboardState.llmHistorySuffix
    let currentExpected = history[currentIndex] + suffix

    let beforeText = textDocumentProxy.documentContextBeforeInput ?? ""
    guard beforeText == currentExpected else {
      self.keyboardState.clearLLMHistory()
      return
    }

    let targetText = self.keyboardState.llmTextHistory[targetIndex]

    self.isPerformingHistoryNavigation = true

    for _ in 0 ..< beforeText.count {
      textDocumentProxy.deleteBackward()
    }

    textDocumentProxy.insertText(targetText + suffix)
    self.keyboardState.llmHistoryIndex = targetIndex

    self.isPerformingHistoryNavigation = false
  }
}

extension KeyboardViewController {

  func undoLLM() {
    guard self.keyboardState.canUndoLLM else { return }
    self.navigateLLMHistory(to: self.keyboardState.llmHistoryIndex - 1)
  }

  func redoLLM() {
    guard self.keyboardState.canRedoLLM else { return }
    self.navigateLLMHistory(to: self.keyboardState.llmHistoryIndex + 1)
  }
}


