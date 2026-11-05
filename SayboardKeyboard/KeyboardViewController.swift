
import ObjectiveC

import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {

  static var llmCompleteObserver: DarwinNotificationObserver?
  static var llmFailedObserver: DarwinNotificationObserver?
  static var llmStartedObserver: DarwinNotificationObserver?
  nonisolated(unsafe) static weak var activeInstance: KeyboardViewController?

  var llmOriginalText = ""
  var isPerformingHistoryNavigation = false
  var pendingAutoActionText: String?
  var llmSelectedText: String?
  var llmDirectSelectedText: String?
  var llmRequestID: UUID?
  var llmDocumentIdentifier: UUID?
  var llmSelectionContextBefore: String?
  var llmSelectionContextAfter: String?
  var llmClipboardOnly = false
  var pendingManualLLMAction: (action: LLMAction, customPromptId: UUID?)?
  var previousSpaceTap: PeriodShortcut.Tap?
  var lastTouchDocumentID: UUID?
  var cursorPreferredColumn: Int?
  var cursorPreferredDocumentID: UUID?
  var liveTranscriptionDocumentID: UUID?
  var liveTranscriptionMarkedText = ""
  var liveTranscriptionCommittedRaw = ""
  var liveTranscriptionPrefix = ""
  var liveTranscriptionRevision = 0
  var liveTranscriptionBlockedToken: String?
  static var blockedLiveSessionToken: String?

  let keyboardState = KeyboardState()
  private let keyboardTraceSession = String(UUID().uuidString.prefix(8))
  private var lastTracedLayoutKey = ""

  var processingTimeoutTimer: Timer?
  var processingStartTime: Date?
  var receivedPingDuringProcessing = false

  override func loadView() {
    let keyboard = KeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
    keyboard.contentHeight = KeyboardMetrics.totalHeight(
      actionBarVisible: false, kind: self.keyboardState.effectiveTypingKind
    )
    keyboard.allowsSelfSizing = true
    keyboard.backgroundColor = KeyboardPalette.backdrop
    keyboard.clipsToBounds = true
    self.inputView = keyboard
    let height = keyboard.heightAnchor.constraint(equalToConstant: keyboard.contentHeight)
    height.priority = UILayoutPriority(rawValue: 999)
    height.isActive = true
    self.heightConstraint = height
    self.recordKeyboardTrace(.inputViewLoaded)
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Altboard provides a microphone key; avoid a duplicate system dictation
    // button below the keyboard on Face ID iPhones.
    self.hasDictationKey = true
    self.keyboardState.bootstrapLayoutSettings()
    self.keyboardState.configureInputModeListButton = { [weak self] button in
      guard !SharedSettings.keyboardGlobeTemporarilyDisabled else { return }
      guard let self else { return }
      button.addTarget(
        self, action: #selector(handleInputModeList(from:with:)),
        for: .allTouchEvents
      )
    }
    self.setupKeyboardView()
    KeyboardHaptics.prepare()
    Self.activeInstance = self
    self.setupTranscriptionObserver()
    self.setupExperimentalLiveObserver()
    self.setupVoiceProgressObserver()
    self.setupSessionObservers()
    self.setupForegroundObserver()
    self.setupLLMObservers()
    self.setupDictationLockObserver()
    self.recordKeyboardTrace(.hostingMounted)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    Self.activeInstance = self
    SharedSettings().defaults.set(true, forKey: "canto.keyboardOpenedAtLeastOnce")
    SharedSettings().synchronize()
    self.keyboardState.refresh()
    if self.lastTouchDocumentID != self.textDocumentProxy.documentIdentifier {
      KeyboardTouchLearning.shared.invalidate()
    }
    self.lastTouchDocumentID = self.textDocumentProxy.documentIdentifier
    self.refreshHostInputTraits()
    self.syncFullAccessIfChanged()
    // Reset transient gestures without tearing down the visible render tree.
    self.keyboardState.keyboardAppearanceRevision &+= 1
    KeyboardHaptics.prepare()
    if self.keyboardState.isRecording {
      self.keyboardState.startLevelPolling()
    } else if !self.keyboardState.isProcessing {
      self.keyboardState.stopLevelPolling()
    }
    self.keyboardState.isTranslationMode = SharedSettings().isTranslationMode
    self.updateKeyboardHeight(actionBarVisible: false)
    self.pingMainAppForSessionStatus()
    self.pingValidator.startIfNeeded(for: self.keyboardState)
    self.keyboardState.appearedAt = CFAbsoluteTimeGetCurrent()
    saveHostBundleId()
    self.keyboardState.syncOnboardingPractice(hostProcessID: self.hostProcess?.pid)
    self.hasDeferredAppearanceInsert = true
    self.applyExperimentalLiveUpdate()
    self.recordKeyboardTrace(.willAppear)
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    KeyboardTouchLearning.shared.invalidate()
    if self.liveTranscriptionDocumentID != nil {
      let token = SharedSettings().dictationSessionToken
      self.liveTranscriptionBlockedToken = token
      Self.blockedLiveSessionToken = token
    }
    if !self.keyboardState.isRecording, !self.keyboardState.isProcessing {
      self.keyboardState.stopLevelPolling()
    }
    self.recordKeyboardTrace(.willDisappear)
  }

  override func didReceiveMemoryWarning() {
    self.recordKeyboardTrace(.memoryWarning)
    super.didReceiveMemoryWarning()
  }

  private func recordKeyboardTrace(_ event: KeyboardLifecycleTrace.Event) {
    let bounds = self.viewIfLoaded?.bounds ?? .zero
    KeyboardLifecycleTrace.record(
      event, session: self.keyboardTraceSession,
      requestedMode: self.keyboardState.keyboardKind,
      effectiveMode: self.keyboardState.effectiveTypingKind,
      viewWidth: bounds.width, viewHeight: bounds.height,
      hostWidth: self.hostGeometry.size.width,
      hostHeight: self.hostGeometry.size.height,
      hostingMounted: self.hostingController != nil,
      hostingInWindow: self.hostingController?.viewIfLoaded?.window != nil,
      nativeSwitchRequired: self.needsInputModeSwitchKey,
      fullAccess: self.keyboardState.hasFullAccess,
      hostBundleHint: SharedSettings().hostBundleId
    )
  }

  func insertTranscribedText() {
    let text = TranscriptionBridge.readTranscription()
    guard let text, !text.isEmpty else {
      DiagnosticLog.write("keyboard: NO TEXT available to insert")
      let settings = SharedSettings()
      settings.synchronize()
      if let outcome = settings.lastDictationOutcome {
        self.keyboardState.dictationOutcome = outcome
      }
      return
    }
    FeatureDiagnostics.record(.bridge, .started)
    self.keyboardState.dictationOutcome = nil
    if !self.isPerformingHistoryNavigation {
      self.keyboardState.clearLLMHistory()
    }
    TranscriptionBridge.clearTranscription()

    if self.liveTranscriptionBlockedToken != nil || Self.blockedLiveSessionToken != nil {
      Self.blockedLiveSessionToken = nil
      self.liveTranscriptionBlockedToken = nil
      self.keyboardState.showFinalOutputPreview(text)
      FeatureDiagnostics.record(.bridge, .fallback)
      return
    }
    if self.completeExperimentalLiveText(text) {
      self.copyFinalTextToClipboardIfEnabled(text)
      self.keyboardState.showFinalOutputPreview(text)
      FeatureDiagnostics.record(.bridge, .completed)
      return
    }
    if self.autoApplyLLMIfNeeded(directText: text) {
      FeatureDiagnostics.record(.bridge, .queued)
      return
    }

    DiagnosticLog.write("keyboard: inserting \(text.count) chars into textDocumentProxy")
    self.insertSpacedText(text)
    FeatureDiagnostics.record(.bridge, .completed)
    self.copyFinalTextToClipboardIfEnabled(text)
    self.keyboardState.showFinalOutputPreview(text)
  }

  func copyFinalTextToClipboardIfEnabled(_ text: String) {
    guard SharedSettings().alsoCopyToClipboard else { return }
    UIPasteboard.general.string = text
  }

  func pingMainAppForSessionStatus() {
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.requestSessionStatus)
  }

  private static let staleFallbackTimeout: TimeInterval = 1.0

  private static var transcriptionObserver: DarwinNotificationObserver?
  private static var voiceProgressObserver: DarwinNotificationObserver?
  private static var dictationStartedObserver: DarwinNotificationObserver?
  private static var dictationStoppedObserver: DarwinNotificationObserver?
  private static var sessionStartedObserver: DarwinNotificationObserver?
  private static var sessionEndedObserver: DarwinNotificationObserver?
  private static var modelLoadingFailedObserver: DarwinNotificationObserver?

  private var heightConstraint: NSLayoutConstraint?
  private var hostingHeightConstraint: NSLayoutConstraint?
  private var actionBarVisible = false

  private var hostingController: UIHostingController<KeyboardHostingRoot>?
  private let hostGeometry = KeyboardHostGeometry()
  private var staleFallbackTimer: Timer?
  private var lastSyncedFullAccess = false
  private var hasPerformedInitialFullAccessSync = false
  private var hasDeferredAppearanceInsert = false
  private let pingValidator = PingValidator()

  private func syncFullAccessIfChanged() {
    let current = self.hasFullAccess
    self.keyboardState.hasFullAccess = current
    // Report the real extension state. The parent can read this only when
    // both signed targets can access the same App Group.
    let settings = SharedSettings()
    settings.defaults.set(CFAbsoluteTimeGetCurrent(), forKey: SharedKey.keyboardProbeTimestamp)
    settings.defaults.set(current, forKey: SharedKey.keyboardProbeFullAccess)
    settings.defaults.set(AppGroup.containerURL != nil, forKey: SharedKey.keyboardProbeGroupAvailable)
    settings.defaults.set(Bundle.main.infoDictionary?["AltboardBuildSHA"] as? String ?? "unstamped",
      forKey: SharedKey.keyboardBuildSHA)
    settings.hasFullAccess = current
    settings.synchronize()
    guard !self.hasPerformedInitialFullAccessSync || current != self.lastSyncedFullAccess else { return }
    self.hasPerformedInitialFullAccessSync = true
    self.lastSyncedFullAccess = current
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.fullAccessChanged)
  }

  private func setupTranscriptionObserver() {
    Self.transcriptionObserver?.stopObserving()
    Self.transcriptionObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.transcriptionReady
    ) {
      DispatchQueue.main.async {
        guard let vc = Self.activeInstance else {
          return
        }
        vc.cancelProcessingTimeout()
        vc.keyboardState.syncDictationLock()
        vc.insertTranscribedText()
        vc.finalizeProcessingPipeline()
      }
    }
  }

  private func setupVoiceProgressObserver() {
    Self.voiceProgressObserver?.stopObserving()
    Self.voiceProgressObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.voiceProgressUpdated
    ) {
      DispatchQueue.main.async {
        guard let vc = Self.activeInstance else { return }
        vc.keyboardState.syncVoiceProcessingProgress()
      }
    }
  }

  private func setupForegroundObserver() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(self.hostDidEnterForeground),
      name: UIApplication.willEnterForegroundNotification,
      object: nil,
    )
  }

  @objc
  private func hostDidEnterForeground() {
    self.syncFullAccessIfChanged()
    self.keyboardState.refresh()
    self.refreshHostInputTraits()
    self.keyboardState.keyboardAppearanceRevision &+= 1
    self.updateKeyboardHeight(actionBarVisible: false)
    KeyboardHaptics.prepare()
    if self.keyboardState.isRecording {
      self.keyboardState.startLevelPolling()
    }
    self.keyboardState.syncOnboardingPractice(hostProcessID: self.hostProcess?.pid)
    self.pingMainAppForSessionStatus()
    self.pingValidator.startIfNeeded(for: self.keyboardState)
    self.keyboardState.appearedAt = CFAbsoluteTimeGetCurrent()
    self.insertTranscribedText()
    self.checkForPendingLLMResult()
  }

  private func setupSessionObservers() {
    Self.dictationStartedObserver?.stopObserving()
    Self.dictationStoppedObserver?.stopObserving()
    Self.dictationStartedObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.dictationStarted
    ) {
      DispatchQueue.main.async {
        guard let vc = Self.activeInstance else {
          return
        }
        vc.staleFallbackTimer?.invalidate()
        vc.staleFallbackTimer = nil
        vc.pingValidator.cancel()
        vc.cancelProcessingTimeout()
        vc.keyboardState.isProcessing = false
        vc.keyboardState.voiceProcessingProgress = nil
        vc.keyboardState.clearFinalOutputPreview()
        vc.keyboardState.isRecording = true
        vc.liveTranscriptionBlockedToken = nil
        Self.blockedLiveSessionToken = nil
        vc.keyboardState.recordingStartedAt = SharedSettings().recordingStartedAt
        vc.keyboardState.isStartingRecording = false
        if !vc.isPerformingHistoryNavigation {
          vc.keyboardState.clearLLMHistory()
        }
        vc.keyboardState.isSessionActive = true
        vc.keyboardState.startLevelPolling()
      }
    }

    Self.dictationStoppedObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.dictationStopped
    ) {
      DispatchQueue.main.async {
        guard let vc = Self.activeInstance else {
          return
        }
        vc.cancelProcessingTimeout()
        vc.keyboardState.stopLevelPolling()
        vc.keyboardState.isRecording = false
        vc.keyboardState.recordingStartedAt = 0
        vc.keyboardState.isStartingRecording = false
        vc.keyboardState.syncModelLoading()
        vc.keyboardState.syncDictationLock()
        vc.insertTranscribedText()
        if vc.liveTranscriptionDocumentID != nil,
           (SharedSettings().dictationCancellationRequested
             || (TranscriptionBridge.readTranscription() ?? "").isEmpty) {
          vc.cancelExperimentalLiveText()
        }
        vc.finalizeProcessingPipeline()
      }
    }

    self.setupSessionLifecycleObservers()
    self.setupModelLoadingObservers()
  }

  private func finalizeProcessingPipeline() {
    self.keyboardState.voiceProcessingProgress = nil
    self.keyboardState.isProcessing = false
    if self.keyboardState.isLLMProcessing {
      self.startProcessingTimeout()
    }
  }

  private func deletePreviousWord() {
    self.previousSpaceTap = nil
    let context = self.textDocumentProxy.documentContextBeforeInput ?? ""
    guard !context.isEmpty else {
      self.textDocumentProxy.deleteBackward()
      return
    }
    var chars = Array(context)
    var count = 0
    // Unicode Character units preserve composed characters and emoji.
    while let last = chars.last, last.isWhitespace {
      chars.removeLast()
      count += 1
    }
    while let last = chars.last, !last.isWhitespace {
      chars.removeLast()
      count += 1
    }
    for _ in 0..<max(1, count) { self.textDocumentProxy.deleteBackward() }
    if !self.isPerformingHistoryNavigation { self.keyboardState.clearLLMHistory() }
  }

  private func deleteAllText() {
    let proxy = self.textDocumentProxy
    // hasText may remain true when there is text after the cursor.
    // Only delete verified preceding text; stop when the host makes no
    // observable progress and bound the number of deletion attempts.
    for _ in 0..<4_096 {
      guard let before = proxy.documentContextBeforeInput, !before.isEmpty else { break }
      proxy.deleteBackward()
      guard proxy.documentContextBeforeInput != before else { break }
    }
    KeyboardTouchLearning.shared.invalidate()
    if !self.isPerformingHistoryNavigation {
      self.keyboardState.clearLLMHistory()
    }
  }

  private func startDictationViaDarwin() {
    let processing = self.keyboardState.isProcessing
    let recording = self.keyboardState.isRecording

    guard !processing, !recording else {
      return
    }
    saveHostBundleId()
    let settings = SharedSettings()
    settings.synchronize()

    settings.dictationSessionToken = UUID().uuidString
    settings.dictationCancellationRequested = false
    settings.synchronize()
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.requestStartDictation)

    self.staleFallbackTimer?.invalidate()
    // The History test field is already in the foreground app. Never redirect
    // out of that field merely because model startup takes longer than 1s.
    if HistoryKeyboardTestSession.isFocused { return }
    self.staleFallbackTimer = Timer.scheduledTimer(
      withTimeInterval: Self.staleFallbackTimeout,
      repeats: false,
    ) { [weak self] _ in
      DispatchQueue.main.async {
        guard let self else { return }
        let sessionActive = self.keyboardState.isSessionActive
        let isRec = self.keyboardState.isRecording
        guard !sessionActive, !isRec else { return }
        self.openDictateDeepLinkFallback(
          reason: "stale fallback fired (no response in \(Self.staleFallbackTimeout)s, session=\(sessionActive) rec=\(isRec))"
        )
      }
    }
  }

  private func openDictateDeepLinkFallback(reason _: String) {
    let settings = SharedSettings()
    settings.isSessionActive = false
    settings.keyboardRequestedDictationAt = CFAbsoluteTimeGetCurrent()
    settings.keyboardRequestedDictation = true
    if settings.dictationSessionToken == nil {
      settings.dictationSessionToken = UUID().uuidString
    }
    settings.synchronize()
    self.keyboardState.isSessionActive = false
    self.keyboardState.isProcessing = false
    guard let url = DeepLink.dictateURL else { return }
    if let openAction = self.keyboardState.openURLAction {
      openAction(url)
    } else {
      self.openURL(url)
    }
  }

}

extension KeyboardViewController {

  func cancelDictationViaDarwin() {
    self.cancelExperimentalLiveText()
    self.staleFallbackTimer?.invalidate()
    self.staleFallbackTimer = nil
    self.cancelProcessingTimeout()
    self.keyboardState.isStartingRecording = false
    self.keyboardState.isRecording = false
    self.keyboardState.recordingStartedAt = 0
    self.keyboardState.isProcessing = false
    self.keyboardState.stopLevelPolling()
    let settings = SharedSettings()
    settings.keyboardRequestedDictation = false
    settings.dictationCancellationRequested = true
    settings.synchronize()
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.requestCancelDictation)
  }

  func stopDictationViaDarwin() {
    self.saveHostBundleId()
    self.keyboardState.isProcessing = true
    self.keyboardState.syncVoiceProcessingProgress()
    self.keyboardState.syncModelLoading()
    self.keyboardState.stopLevelPolling()
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.requestStopDictation)
    self.startProcessingTimeout()
  }

  private func setupSessionLifecycleObservers() {
    Self.sessionStartedObserver?.stopObserving()
    Self.sessionEndedObserver?.stopObserving()
    Self.sessionStartedObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.sessionStarted
    ) {
      DispatchQueue.main.async {
        guard let vc = Self.activeInstance else { return }
        let isProc = vc.keyboardState.isProcessing
        vc.pingValidator.cancel()
        vc.keyboardState.isSessionActive = true
        if isProc || vc.keyboardState.isLLMProcessing {
          vc.receivedPingDuringProcessing = true
        } else {
          vc.cancelProcessingTimeout()
        }
      }
    }

    Self.sessionEndedObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.sessionEnded
    ) {
      DispatchQueue.main.async {
        guard let vc = Self.activeInstance else { return }
        let finalizing = vc.keyboardState.isProcessing
        if !finalizing { vc.cancelProcessingTimeout() }
        vc.keyboardState.stopLevelPolling()
        vc.keyboardState.isSessionActive = false
        vc.keyboardState.isRecording = false
        vc.keyboardState.recordingStartedAt = 0
        vc.keyboardState.isStartingRecording = false
        vc.keyboardState.isProcessing = finalizing
        if finalizing { vc.startProcessingTimeout() }
      }
    }
  }

  private func setupModelLoadingObservers() {
    Self.modelLoadingFailedObserver?.stopObserving()
    Self.modelLoadingFailedObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.modelLoadingFailed
    ) {
      DispatchQueue.main.async {
        guard let vc = Self.activeInstance else { return }
        vc.resetProcessingState()
      }
    }
  }
}

extension KeyboardViewController {

  func updateKeyboardHeight(actionBarVisible: Bool) {
    self.actionBarVisible = actionBarVisible
    self.applyKeyboardHeight()
  }

  private func setupKeyboardView() {
    guard self.hostingController == nil else { return }
    let root = KeyboardHostingRoot(
      proxy: self.makeKeyboardProxy(), keyboardState: self.keyboardState,
      geometry: self.hostGeometry
    )
    let hosting = UIHostingController(rootView: root)
    hosting.safeAreaRegions = []
    hosting.sizingOptions = []
    hosting.view.backgroundColor = .clear
    hosting.view.isOpaque = false
    hosting.view.translatesAutoresizingMaskIntoConstraints = false

    self.addChild(hosting)
    self.view.addSubview(hosting.view)
    let initialHeight = KeyboardMetrics.totalHeight(
      actionBarVisible: false, kind: self.keyboardState.effectiveTypingKind
    )
    let hostingHeight = hosting.view.heightAnchor.constraint(equalToConstant: initialHeight)
    NSLayoutConstraint.activate([
      hosting.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
      hosting.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
      hosting.view.topAnchor.constraint(equalTo: self.view.topAnchor),
      hostingHeight,
    ])
    self.hostingHeightConstraint = hostingHeight
    self.hostingController = hosting
    hosting.didMove(toParent: self)
  }

  private func applyKeyboardHeight() {
    let target = KeyboardMetrics.totalHeight(
      actionBarVisible: self.actionBarVisible,
      kind: self.keyboardState.effectiveTypingKind
    )
    if let keyboard = self.inputView as? KeyboardInputView {
      keyboard.contentHeight = target
    }
    if let height = self.heightConstraint, height.constant != target {
      height.constant = target
    }
    if let height = self.hostingHeightConstraint, height.constant != target {
      height.constant = target
    }
    self.hostGeometry.update(width: self.view.bounds.width, height: target)
    self.view.setNeedsLayout()
  }

  private func makeKeyboardProxy() -> KeyboardProxy {
    KeyboardProxy(
      insertText: { [weak self] text in
        self?.previousSpaceTap = nil
        self?.textDocumentProxy.insertText(text)
        self?.refreshHostInputTraits()
      },
      documentContextBeforeInput: { [weak self] in
        self?.textDocumentProxy.documentContextBeforeInput
      },
      insertSpace: { [weak self] in
        self?.insertSpace()
        self?.refreshHostInputTraits()
      },
      deleteBackward: { [weak self] in
        self?.previousSpaceTap = nil
        // Only an actual Delete keypress is evidence of a touch repair.
        // Candidate replacements also call this proxy and must not teach hitboxes.
        self?.textDocumentProxy.deleteBackward()
        self?.refreshHostInputTraits()
      },
      deleteWordBackward: { [weak self] in
        KeyboardTouchLearning.shared.invalidate()
        self?.deletePreviousWord()
        self?.refreshHostInputTraits()
      },
      deleteAll: { [weak self] in
        self?.previousSpaceTap = nil
        self?.deleteAllText()
        self?.refreshHostInputTraits()
      },
      advanceToNextInputMode: { [weak self] in
        self?.advanceToNextInputMode()
      },
      openURL: { [weak self] url in
        self?.openURL(url)
      },
      startDictation: { [weak self] in
        self?.startDictationViaDarwin()
      },
      stopDictation: { [weak self] in
        self?.stopDictationViaDarwin()
      },
      cancelDictation: { [weak self] in
        self?.cancelDictationViaDarwin()
      },
      resolveHost: { [weak self] in
        self?.saveHostBundleId()
      },
      requestLLMProcessing: { [weak self] action, customPromptId in
        self?.requestLLMProcessing(action: action, customPromptId: customPromptId)
      },
      requestLLMClipboard: { [weak self] in
        self?.requestLLMClipboardProcessing()
      },
      adjustTextPosition: { [weak self] offset in
        KeyboardTouchLearning.shared.invalidate()
        self?.previousSpaceTap = nil
        self?.resetCursorVerticalState()
        self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
      },
      moveCursorVertically: { [weak self] steps in
        self?.moveCursorVertically(steps)
      },
      resetCursorVerticalState: { [weak self] in
        self?.resetCursorVerticalState()
      },
      undoLLM: { [weak self] in self?.undoLLM() },
      redoLLM: { [weak self] in self?.redoLLM() },
      setActionBarVisible: { [weak self] visible in
        self?.updateKeyboardHeight(actionBarVisible: visible)
      },
    )
  }
}

extension KeyboardViewController {

  private static var dictationLockObserver: DarwinNotificationObserver?

  private func setupDictationLockObserver() {
    Self.dictationLockObserver?.stopObserving()
    Self.dictationLockObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.dictationLockChanged
    ) {
      DispatchQueue.main.async {
        guard let vc = Self.activeInstance else { return }
        vc.keyboardState.syncDictationLock()
        guard vc.keyboardState.isDictationLocked, vc.staleFallbackTimer?.isValid == true else { return }
        vc.staleFallbackTimer?.invalidate()
        vc.staleFallbackTimer = nil
        vc.openUnlockLink()
      }
    }
  }

  private func openUnlockLink() {
    guard let url = DeepLink.unlockURL else { return }
    if let openAction = self.keyboardState.openURLAction {
      openAction(url)
    } else {
      self.openURL(url)
    }
  }
}

extension KeyboardViewController {

  override func textWillChange(_ textInput: (any UITextInput)?) {
    super.textWillChange(textInput)
    self.refreshHostInputTraits()
  }

  override func textDidChange(_ textInput: (any UITextInput)?) {
    super.textDidChange(textInput)
    let currentDocument = self.textDocumentProxy.documentIdentifier
    if self.lastTouchDocumentID != currentDocument {
      KeyboardTouchLearning.shared.invalidate()
      self.lastTouchDocumentID = currentDocument
      // A host can switch fields without another appearance callback.
      self.keyboardState.keyboardAppearanceRevision &+= 1
      self.view.setNeedsLayout()
      self.recordKeyboardTrace(.documentChanged)
    }
    self.refreshHostInputTraits()
    self.keyboardState.textContextRevision &+= 1
    self.syncInputModeSwitchKey()
    self.insertDeferredAppearanceText()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    self.insertDeferredAppearanceText()
    self.recordKeyboardTrace(.didAppear)
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    self.recordKeyboardTrace(.didDisappear)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    self.hostGeometry.update(
      width: self.view.bounds.width,
      height: KeyboardMetrics.totalHeight(
        actionBarVisible: self.actionBarVisible, kind: self.keyboardState.effectiveTypingKind
      )
    )
    let width = self.view.bounds.width
    let height = self.view.bounds.height
    let hostValid = self.hostGeometry.size.width > 1 && self.hostGeometry.size.height > 1
    let inWindow = self.hostingController?.viewIfLoaded?.window != nil
    let signature = "\(width.isFinite ? Int(width.rounded()) : -1):\(height.isFinite ? Int(height.rounded()) : -1):\(hostValid):\(inWindow)"
    if self.lastTracedLayoutKey != signature {
      self.lastTracedLayoutKey = signature
      self.recordKeyboardTrace(.layoutChanged)
    }
  }

  private func refreshHostInputTraits() {
    let proxy = self.textDocumentProxy
    let traits = KeyboardHostInputTraits(
      keyboardType: proxy.keyboardType ?? .default,
      returnKeyType: proxy.returnKeyType ?? .default,
      contentType: proxy.textContentType?.rawValue,
      autocapitalizationType: proxy.autocapitalizationType ?? .sentences,
      enablesReturnKeyAutomatically: proxy.enablesReturnKeyAutomatically ?? false,
      hasText: proxy.hasText
        || !(proxy.documentContextBeforeInput ?? "").isEmpty
        || !(proxy.documentContextAfterInput ?? "").isEmpty
        || !(proxy.selectedText ?? "").isEmpty
    )
    if traits != self.keyboardState.hostInputTraits {
      self.keyboardState.hostInputTraits = traits
    }
  }

  private func syncInputModeSwitchKey() {
    let needsKey = self.needsInputModeSwitchKey
    guard needsKey != self.keyboardState.needsInputModeSwitchKey else { return }
    self.keyboardState.needsInputModeSwitchKey = needsKey
    SharedSettings().needsInputModeSwitchKey = needsKey
    self.recordKeyboardTrace(.switchRequirementChanged)
  }

  private func insertDeferredAppearanceText() {
    guard self.hasDeferredAppearanceInsert else { return }
    self.hasDeferredAppearanceInsert = false
    self.insertTranscribedText()
    self.checkForPendingLLMResult()
  }
}


