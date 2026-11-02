
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
  var llmSelectionContextBefore: String?
  var llmSelectionContextAfter: String?
  var llmClipboardOnly = false
  var pendingManualLLMAction: (action: LLMAction, customPromptId: UUID?)?
  var previousSpaceTap: PeriodShortcut.Tap?

  let keyboardState = KeyboardState()

  var processingTimeoutTimer: Timer?
  var processingStartTime: Date?
  var receivedPingDuringProcessing = false

  override func loadView() {
    super.loadView()
    view.backgroundColor = KeyboardPalette.backdrop
    view.clipsToBounds = true

    if let inputView = view as? UIInputView {
      inputView.allowsSelfSizing = true
    }
  }

  override func updateViewConstraints() {
    super.updateViewConstraints()
    if self.heightConstraint == nil {
      for constraint in view.constraintsAffectingLayout(for: .vertical) {
        constraint.priority = .defaultHigh
      }
      let kind = self.keyboardState.keyboardKind
      let initialHeight = KeyboardMetrics.totalHeight(actionBarVisible: false, kind: kind)
      let hc = view.heightAnchor.constraint(equalToConstant: initialHeight)
      hc.priority = UILayoutPriority(rawValue: 999)
      hc.isActive = true
      self.heightConstraint = hc
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    self.keyboardState.bootstrapLayoutSettings()
    KeyboardHaptics.prepare()
    Self.activeInstance = self
    self.setupTranscriptionObserver()
    self.setupVoiceProgressObserver()
    self.setupSessionObservers()
    self.setupForegroundObserver()
    self.setupLLMObservers()
    self.setupDictationLockObserver()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    Self.activeInstance = self
    SharedSettings().defaults.set(true, forKey: "canto.keyboardOpenedAtLeastOnce")
    SharedSettings().synchronize()
    if self.hostingController == nil {
      self.setupKeyboardView()
    }
    self.keyboardState.refresh()
    KeyboardHaptics.prepare()
    if self.keyboardState.isRecording {
      self.keyboardState.startLevelPolling()
    } else if !self.keyboardState.isProcessing {
      self.keyboardState.stopLevelPolling()
    }
    self.keyboardState.isTranslationMode = SharedSettings().isTranslationMode
    self.updateKeyboardHeight(actionBarVisible: false)
    self.syncFullAccessIfChanged()
    self.pingMainAppForSessionStatus()
    self.pingValidator.startIfNeeded(for: self.keyboardState)
    self.keyboardState.appearedAt = CFAbsoluteTimeGetCurrent()
    saveHostBundleId()
    self.keyboardState.syncOnboardingPractice(hostProcessID: self.hostProcess?.pid)
    self.hasDeferredAppearanceInsert = true
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if !self.keyboardState.isRecording, !self.keyboardState.isProcessing {
      self.keyboardState.stopLevelPolling()
    }
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
    self.keyboardState.dictationOutcome = nil
    if !self.isPerformingHistoryNavigation {
      self.keyboardState.clearLLMHistory()
    }
    TranscriptionBridge.clearTranscription()

    if self.autoApplyLLMIfNeeded(directText: text) {
      return
    }

    DiagnosticLog.write("keyboard: inserting \(text.count) chars into textDocumentProxy")
    self.insertSpacedText(text)
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

  private var hostingController: UIHostingController<KeyboardView>?
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
    while textDocumentProxy.hasText {
      textDocumentProxy.deleteBackward()
    }
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

  func setupKeyboardView() {
    let proxy = self.makeKeyboardProxy()
    let keyboardView = KeyboardView(proxy: proxy, keyboardState: self.keyboardState)
    let hosting = UIHostingController(rootView: keyboardView)
    hosting.safeAreaRegions = []
    hosting.view.backgroundColor = KeyboardPalette.backdrop
    hosting.view.translatesAutoresizingMaskIntoConstraints = false

    self.addChild(hosting)
    self.view.addSubview(hosting.view)
    hosting.didMove(toParent: self)

    let kind = self.keyboardState.keyboardKind
    let initialHeight = KeyboardMetrics.totalHeight(actionBarVisible: false, kind: kind)
    let hostingHeight = hosting.view.heightAnchor.constraint(equalToConstant: initialHeight)
    NSLayoutConstraint.activate([
      hosting.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
      hosting.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
      hosting.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
      hostingHeight,
    ])
    self.hostingHeightConstraint = hostingHeight

    self.hostingController = hosting
  }

  private func applyKeyboardHeight() {
    guard let hc = self.heightConstraint else { return }
    let base = KeyboardMetrics.totalHeight(
      actionBarVisible: self.actionBarVisible,
      kind: self.keyboardState.keyboardKind,
    )
    let target = base
    guard hc.constant != target else { return }
    hc.constant = target
    self.hostingHeightConstraint?.constant = target
    UIView.performWithoutAnimation {
      self.view.layoutIfNeeded()
      self.view.superview?.layoutIfNeeded()
    }
  }

  private func makeKeyboardProxy() -> KeyboardProxy {
    KeyboardProxy(
      insertText: { [weak self] text in
        self?.previousSpaceTap = nil
        self?.textDocumentProxy.insertText(text)
      },
      documentContextBeforeInput: { [weak self] in
        self?.textDocumentProxy.documentContextBeforeInput
      },
      insertSpace: { [weak self] in
        self?.insertSpace()
      },
      deleteBackward: { [weak self] in
        self?.previousSpaceTap = nil
        self?.textDocumentProxy.deleteBackward()
      },
      deleteWordBackward: { [weak self] in
        self?.deletePreviousWord()
      },
      deleteAll: { [weak self] in
        self?.previousSpaceTap = nil
        self?.deleteAllText()
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
        self?.previousSpaceTap = nil
        self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
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

  override func textDidChange(_ textInput: (any UITextInput)?) {
    super.textDidChange(textInput)
    self.keyboardState.textContextRevision &+= 1
    self.syncInputModeSwitchKey()
    self.insertDeferredAppearanceText()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    self.insertDeferredAppearanceText()
  }

  private func syncInputModeSwitchKey() {
    let needsKey = self.needsInputModeSwitchKey
    guard needsKey != self.keyboardState.needsInputModeSwitchKey else { return }
    self.keyboardState.needsInputModeSwitchKey = needsKey
    SharedSettings().needsInputModeSwitchKey = needsKey
  }

  private func insertDeferredAppearanceText() {
    guard self.hasDeferredAppearanceInsert else { return }
    self.hasDeferredAppearanceInsert = false
    self.insertTranscribedText()
    self.checkForPendingLLMResult()
  }
}
