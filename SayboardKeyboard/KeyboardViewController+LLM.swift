
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
        vc.keyboardState.isLLMProcessing = true
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
        vc.insertPendingAutoActionFallback()
        vc.keyboardState.isLLMProcessing = false
        vc.keyboardState.isProcessing = false
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
        self.llmDocumentIdentifier = proxy.documentIdentifier
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
      self.llmDocumentIdentifier = self.textDocumentProxy.documentIdentifier
      self.llmSelectionContextBefore = self.textDocumentProxy.documentContextBeforeInput
      self.llmSelectionContextAfter = self.textDocumentProxy.documentContextAfterInput
      self.llmOriginalText = ""
      self.pendingAutoActionText = nil
    }

    self.keyboardState.isLLMProcessing = true

    if self.keyboardState.llmTextHistory.isEmpty {
      self.keyboardState.llmTextHistory = [inputText]
      self.keyboardState.llmHistoryIndex = 0
    } else {
      let idx = self.keyboardState.llmHistoryIndex
      self.keyboardState.llmTextHistory = Array(self.keyboardState.llmTextHistory.prefix(idx + 1))
    }

    let language = Self.detectLanguage(from: inputText)

    let settings = SharedSettings()
    if settings.dictationSessionToken == nil {
      settings.dictationSessionToken = UUID().uuidString
      settings.synchronize()
    }

    let request = LLMRequest(
      text: inputText,
      action: action,
      customPromptId: customPromptId,
      language: language,
    )
    self.llmRequestID = request.requestID
    // Prevent an earlier response from being reused by the next action.
    LLMBridge.clearResult()
    LLMBridge.clearRequest()
    guard LLMBridge.writeRequest(request) else {
      self.keyboardState.llmError = .storageUnavailable
      self.insertPendingAutoActionFallback()
      self.keyboardState.clearLLMHistory()
      self.finishLLMInsertion()
      return
    }
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
    guard LLMBridge.hasResult() else { return }
    guard let result = LLMBridge.readResult(matching: self.llmRequestID),
          !result.isEmpty else {
      // A response owned by a previous keyboard/request must never enter
      // the currently focused document.
      LLMBridge.clearResult()
      return
    }
    self.insertLLMResult()
  }

  private static func detectLanguage(from text: String) -> String? {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    guard let dominant = recognizer.dominantLanguage else { return nil }
    return dominant.rawValue
  }

  private func currentLLMFieldMatches() -> Bool {
    guard let document = self.llmDocumentIdentifier else { return false }
    let proxy = self.textDocumentProxy
    return proxy.documentIdentifier == document
      && proxy.documentContextBeforeInput == self.llmSelectionContextBefore
      && proxy.documentContextAfterInput == self.llmSelectionContextAfter
      && proxy.selectedText == self.llmDirectSelectedText
  }

  private func insertPendingAutoActionFallback() {
    guard let fallbackText = self.pendingAutoActionText else { return }
    if self.currentLLMFieldMatches() {
      self.keyboardState.llmHistorySuffix = self.insertSpacedText(fallbackText).trailing
      self.copyFinalTextToClipboardIfEnabled(fallbackText)
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
        LLMBridge.clearResult()
        return
      }
      DiagnosticLog.write("llm/kb: notified complete but bridge held no result")
      self.insertPendingAutoActionFallback()
      self.keyboardState.isLLMProcessing = false
      self.keyboardState.isProcessing = false
      return
    }
    DiagnosticLog.write("llm/kb: inserting \(result.count) chars")

    if self.llmClipboardOnly {
      UIPasteboard.general.string = result
      self.keyboardState.showFinalOutputPreview("Rewrite copied. Paste to replace.")
      self.keyboardState.clearLLMHistory()
      self.finishLLMInsertion()
      return
    }
    if let originalSelection = self.llmSelectedText {
      // Never overwrite a changed selection after asynchronous inference.
      let matches = textDocumentProxy.documentIdentifier == self.llmDocumentIdentifier
        && textDocumentProxy.selectedText == originalSelection
        && textDocumentProxy.documentContextBeforeInput == self.llmSelectionContextBefore
        && textDocumentProxy.documentContextAfterInput == self.llmSelectionContextAfter
      if matches {
        textDocumentProxy.insertText(result)
        self.keyboardState.showFinalOutputPreview("Selected text rewritten")
      } else {
        UIPasteboard.general.string = result
        self.keyboardState.showFinalOutputPreview("Selection changed. Rewrite copied.")
      }
      self.keyboardState.clearLLMHistory()
      self.finishLLMInsertion()
      return
    }

    guard self.currentLLMFieldMatches() else {
      UIPasteboard.general.string = result
      self.keyboardState.showFinalOutputPreview("Input changed. Rewrite copied.")
      self.keyboardState.clearLLMHistory()
      self.finishLLMInsertion()
      return
    }

    let currentBeforeText = textDocumentProxy.documentContextBeforeInput ?? ""
    let expected = self.llmOriginalText
    guard expected.isEmpty || currentBeforeText == expected else {
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
    self.copyFinalTextToClipboardIfEnabled(result)
    if self.pendingAutoActionText != nil {
      self.keyboardState.showFinalOutputPreview(result)
    }

    self.keyboardState.llmTextHistory.append(result)
    self.keyboardState.llmHistoryIndex = self.keyboardState.llmTextHistory.count - 1

    self.finishLLMInsertion()
  }

  private func finishLLMInsertion() {
    LLMBridge.clearResult()
    LLMBridge.clearRequest()
    self.keyboardState.isLLMProcessing = false
    self.keyboardState.isProcessing = false
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
    let suffix = self.keyboardState.llmHistorySuffix
    let currentExpected = self.keyboardState.llmTextHistory[currentIndex] + suffix

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
    self.copyFinalTextToClipboardIfEnabled(targetText)
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
