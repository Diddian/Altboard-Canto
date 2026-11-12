
import ObjectiveC

import SwiftUI
import UIKit

// Keep Apple's primary UIInputView and its stable self-sizing lifecycle.
// The view opts into the standard system-controlled input click protocol.
extension UIInputView: @retroactive UIInputViewAudioFeedback {
  public var enableInputClicksWhenVisible: Bool { true }
}

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
  var dictationRequestToken: String?
  var dictationDocumentID: UUID?
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
  var liveTranscriptionDocumentEpoch: UUID?
  var liveTranscriptionOwnerToken: String?
  var liveTranscriptionContextAfter: String?
  var liveTranscriptionMarkedText = ""
  var liveTranscriptionCommittedRaw = ""
  var liveTranscriptionPrefix = ""
  var liveTranscriptionRevision = 0
  var liveTranscriptionBlockedToken: String?
  static var blockedLiveSessionToken: String?

  let keyboardState = KeyboardState()
  private let keyboardTraceSession = String(UUID().uuidString.prefix(8))
  private var lastTracedLayoutKey = ""
  private var renderProbeGeneration = 0
  private var missingRowsRefreshAttempted = false
  private var lastObservedHostHasText: Bool?
  private var documentIdentifierUnavailableReported = false
  private var memoryWatchTimer: Timer?
  private var firstLoadForBuild: Bool?
  private var lastObservedDocumentInputModeLanguage: String?
  private var initialStateReady = false
  #if !APPSTORE
  private var liveDebugHUD: KeyboardLiveDebugHUD?
  #endif

  var processingTimeoutTimer: Timer?
  var processingStartTime: Date?
  var receivedPingDuringProcessing = false

  override func loadView() {
    self.traceFirstKeyboardLoad()
    super.loadView()
    view.backgroundColor = .clear
    view.isOpaque = false
    view.clipsToBounds = true

    if let inputView = view as? UIInputView {
      inputView.allowsSelfSizing = true
    }
    #if !APPSTORE
    self.refreshLiveDebugHUD()
    #endif
    self.recordKeyboardTrace(.inputViewLoaded)
  }

  override func updateViewConstraints() {
    super.updateViewConstraints()
    if self.heightConstraint == nil {
      for constraint in view.constraintsAffectingLayout(for: .vertical) {
        constraint.priority = .defaultHigh
      }
      let kind = self.keyboardState.effectiveTypingKind
      let initialHeight = KeyboardMetrics.totalHeight(actionBarVisible: false, kind: kind)
      let hc = view.heightAnchor.constraint(equalToConstant: initialHeight)
      hc.priority = UILayoutPriority(rawValue: 999)
      hc.isActive = true
      self.heightConstraint = hc
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Altboard provides a microphone key; avoid a duplicate system dictation
    // button below the keyboard on Face ID iPhones.
    self.hasDictationKey = true
    self.keyboardState.bootstrapLayoutSettings()
    #if !APPSTORE
    self.keyboardState.liveDebugAction = { [weak self] event in
      self?.recordLiveDebugAction(event)
    }
    #endif
    self.keyboardState.configureInputModeListButton = { [weak self] button in
      guard let self else { return }
      button.removeTarget(self, action: #selector(handleInputModeList(from:with:)),
                          for: .allTouchEvents)
      FeatureDiagnostics.record(.keyboardGlobe, .completed)
      button.addTarget(
        self, action: #selector(handleInputModeList(from:with:)),
        for: .allTouchEvents
      )
      #if !APPSTORE
      button.addTarget(self, action: #selector(recordNativeGlobeTouch), for: .touchDown)
      #endif
    }
    // Prewarm only when the keyboard is about to enter a visible window.
    Self.activeInstance = self
    self.setupTranscriptionObserver()
    self.setupExperimentalLiveObserver()
    self.setupVoiceProgressObserver()
    self.setupSessionObservers()
    self.setupForegroundObserver()
    self.setupInputModeObserver()
    self.setupLLMObservers()
    self.setupDictationLockObserver()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    Self.activeInstance = self
    SharedSettings().defaults.set(true, forKey: "canto.keyboardOpenedAtLeastOnce")
    SharedSettings().synchronize()
    self.keyboardState.refresh()
    self.syncFullAccessIfChanged()
    self.initialStateReady = true
    if self.hostingController == nil {
      self.setupKeyboardView()
    }
    #if !APPSTORE
    self.refreshLiveDebugHUD()
    #endif
    let document = self.availableDocumentIdentifier()
    if document == nil || self.lastTouchDocumentID != document {
      self.keyboardState.documentEpoch = UUID()
      KeyboardTouchLearning.shared.invalidate()
    }
    // Do not reuse field-specific touch state when UIKit cannot identify it.
    self.lastTouchDocumentID = document
    self.recoverActiveDictationAfterReentry()
    self.refreshHostInputTraits()
    self.lastObservedHostHasText = self.textDocumentProxy.hasText
    // Reset transient gestures without tearing down the visible render tree.
    self.keyboardState.keyboardAppearanceRevision &+= 1
    self.missingRowsRefreshAttempted = false
    KeyboardHaptics.prepare()
    if self.keyboardState.isRecording {
      self.keyboardState.startLevelPolling()
    } else if !self.keyboardState.isProcessing {
      self.keyboardState.stopLevelPolling()
    }
    self.keyboardState.isTranslationMode = SharedSettings().isTranslationMode
    self.updateKeyboardHeight(actionBarVisible: false)
    self.pingValidator.startIfNeeded(for: self.keyboardState)
    self.pingMainAppForSessionStatus()
    self.keyboardState.appearedAt = CFAbsoluteTimeGetCurrent()
    self.resumeProcessingTimeoutIfNeeded()
    saveHostBundleId()
    self.keyboardState.syncOnboardingPractice(hostProcessID: self.hostProcess?.pid)
    self.hasDeferredAppearanceInsert = true
    self.applyExperimentalLiveUpdate()
    self.lastObservedDocumentInputModeLanguage = self.textDocumentProxy.documentInputMode?.primaryLanguage
    self.recordKeyboardTrace(.willAppear)
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    self.staleFallbackTimer?.invalidate()
    self.staleFallbackTimer = nil
    self.warmStartSessionAcknowledged = false
    self.pingValidator.cancel()
    self.stopMemoryWatch()
    KeyboardHaptics.suspend()
    self.renderProbeGeneration &+= 1
    KeyboardTouchLearning.shared.invalidate()
    if self.liveTranscriptionDocumentID != nil {
      let token = self.liveTranscriptionOwnerToken
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

  /// One idle-time memory checkpoint roughly every eight seconds while visible.
  /// Never samples per key, never uses host text, and stops on disappearance.
  private func startMemoryWatch() {
    #if !APPSTORE
    guard self.memoryWatchTimer == nil else { return }
    self.memoryWatchTimer = Timer.scheduledTimer(
      timeInterval: 8, target: self, selector: #selector(sampleMemoryWhileVisible),
      userInfo: nil, repeats: true
    )
    #endif
  }

  private func stopMemoryWatch() {
    self.memoryWatchTimer?.invalidate()
    self.memoryWatchTimer = nil
  }

  @objc private func sampleMemoryWhileVisible() {
    guard self.viewIfLoaded?.window != nil else { return }
    self.recordKeyboardTrace(.memorySample)
  }

  private func recordKeyboardTrace(
    _ event: KeyboardLifecycleTrace.Event,
    renderProbe: KeyboardLifecycleTrace.RenderProbe? = nil
  ) {
    let bounds = self.viewIfLoaded?.bounds ?? .zero
    KeyboardLifecycleTrace.record(
      event, session: self.keyboardTraceSession,
      requestedMode: self.keyboardState.keyboardKind,
      effectiveMode: self.keyboardState.effectiveTypingKind,
      fallbackReason: self.initialStateReady
        ? self.keyboardState.basicTypingFallbackReason?.rawValue : nil,
      viewWidth: bounds.width, viewHeight: bounds.height,
      hostWidth: self.hostGeometry.size.width,
      hostHeight: self.hostGeometry.size.height,
      hostingMounted: self.hostingController != nil,
      hostingInWindow: self.hostingController?.viewIfLoaded?.window != nil,
      nativeSwitchRequired: self.needsInputModeSwitchKey,
      fullAccess: self.keyboardState.hasFullAccess,
      hostBundleHint: SharedSettings().hostBundleId,
      firstLoadForBuild: self.firstLoadForBuild,
      startupReady: self.initialStateReady,
      inputModeProbe: self.inputModeProbe(for: event),
      renderProbe: renderProbe
    )
    #if !APPSTORE
    self.liveDebugHUD?.recordLifecycle(
      event: event.rawValue,
      requestedMode: self.keyboardState.keyboardKind.rawValue,
      effectiveMode: self.keyboardState.effectiveTypingKind.rawValue,
      fallbackReason: self.initialStateReady
        ? self.keyboardState.basicTypingFallbackReason?.rawValue : nil,
      runtimeLanguage: self.primaryLanguage,
      startupReady: self.initialStateReady,
      actualHeight: bounds.height,
      targetHeight: KeyboardMetrics.totalHeight(
        actionBarVisible: self.actionBarVisible, kind: self.keyboardState.effectiveTypingKind
      ),
      keyboardType: self.keyboardState.hostInputTraits.keyboardType.rawValue,
      probe: renderProbe
    )
    #endif
  }

  /// Record before UIKit/SwiftUI keyboard view construction. The marker survives
  /// extension restarts and is reset by a new build SHA, including IPA updates.
  #if !APPSTORE
  private func refreshLiveDebugHUD() {
    let enabled = (AppGroup.sharedDefaults?.object(forKey: SharedKey.keyboardLiveDebugHUD) as? Bool) ?? true
    if !enabled {
      self.liveDebugHUD?.removeFromSuperview()
      self.liveDebugHUD = nil
      return
    }
    if let hud = self.liveDebugHUD {
      self.view.bringSubviewToFront(hud)
      return
    }
    let hud = KeyboardLiveDebugHUD(frame: .zero)
    hud.translatesAutoresizingMaskIntoConstraints = false
    self.view.addSubview(hud)
    NSLayoutConstraint.activate([
      hud.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
      hud.widthAnchor.constraint(equalTo: self.view.widthAnchor, multiplier: 0.90),
      hud.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -14),
      hud.heightAnchor.constraint(equalToConstant: 42),
    ])
    self.liveDebugHUD = hud
  }

  private func recordLiveDebugAction(_ event: KeyboardLiveDebugAction) {
    self.liveDebugHUD?.recordAction(event)
  }

  @objc private func recordNativeGlobeTouch() {
    self.recordLiveDebugAction(.globeTouched)
  }
  #endif

  private func traceFirstKeyboardLoad() {
    #if !APPSTORE
    let build = Bundle.main.infoDictionary?["AltboardBuildSHA"] as? String
    let defaults = AppGroup.sharedDefaults
    let marker = "canto.keyboardDiagnostics.firstLoadBuildSHA"
    if let build, !build.isEmpty, let defaults {
      self.firstLoadForBuild = defaults.string(forKey: marker) != build
    }
    self.recordKeyboardTrace(.loadViewStarting)
    if self.firstLoadForBuild == true, let build, let defaults {
      defaults.set(build, forKey: marker)
      defaults.synchronize()
    }
    #endif
  }

  /// These are mode hints from the running extension, not proof that the
  /// system selected Altboard rather than another keyboard.
  private func inputModeProbe(
    for event: KeyboardLifecycleTrace.Event
  ) -> KeyboardLifecycleTrace.InputModeProbe? {
    #if !APPSTORE
    switch event {
    case .willAppear, .didAppear, .willDisappear, .didDisappear,
         .documentChanged, .inputModeChanged:
      let mode = self.textDocumentProxy.documentInputMode
      let available = UITextInputMode.activeInputModes
        .compactMap { Self.safeLanguageTag($0.primaryLanguage) }
      return .init(
        documentModePresent: mode != nil,
        documentLanguage: Self.safeLanguageTag(mode?.primaryLanguage),
        extensionLanguage: Self.safeLanguageTag(self.primaryLanguage),
        availableLanguages: Array(available.prefix(16)),
        requestedKeyboardType: self.textDocumentProxy.keyboardType?.rawValue ?? -1
      )
    default:
      return nil
    }
    #else
    return nil
    #endif
  }

  private static func safeLanguageTag(_ value: String?) -> String? {
    guard let value, (1...35).contains(value.utf8.count) else { return nil }
    let allowed = value.utf8.allSatisfy { byte in
      (65...90).contains(byte) || (97...122).contains(byte)
        || (48...57).contains(byte) || byte == 45
    }
    return allowed ? value : nil
  }

  /// One delayed, cancellable checkpoint per appearance or field transition.
  /// Never poll during typing or retain host text or UIKit touch coordinates.
  private func scheduleRenderCheckpoint(checkpoint: String) {
    #if !APPSTORE
    self.renderProbeGeneration &+= 1
    let generation = self.renderProbeGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
      guard let self, self.renderProbeGeneration == generation else { return }
      self.captureRenderCheckpoint(checkpoint: checkpoint)
    }
    #endif
  }

  private static func traceDimension(_ value: CGFloat) -> Int {
    guard value.isFinite else { return -1 }
    return max(-1, min(4_096, Int(value.rounded())))
  }

  private static func traceAlpha(_ value: CGFloat) -> Int {
    guard value.isFinite else { return -1 }
    return max(0, min(100, Int((value * 100).rounded())))
  }

  private func captureRenderCheckpoint(checkpoint: String) {
    #if !APPSTORE
    guard let input = self.viewIfLoaded else { return }
    let hosted = self.hostingController?.viewIfLoaded
    let hostingFrame = hosted.map { $0.convert($0.bounds, to: input) } ?? .zero
    var stack: [UIView] = hosted.map { [$0] } ?? []
    var scanned = 0
    var touchCount = 0
    var touchInWindow = 0
    var touchHitCount = 0

    // The actual UIKit touch views are more informative than SwiftUI onAppear.
    // Cap the traversal so diagnostics cannot stall a keyboard extension.
    while let node = stack.popLast(), scanned < 256 {
      scanned += 1
      if let touch = node as? ImmediateKeyTouchView {
        touchCount += 1
        if touch.window != nil && touch.bounds.width > 1 && touch.bounds.height > 1 {
          touchInWindow += 1
          let point = touch.convert(
            CGPoint(x: touch.bounds.midX, y: touch.bounds.midY), to: input
          )
          if input.bounds.contains(point),
             let target = input.hitTest(point, with: nil),
             (target === touch || target.isDescendant(of: touch)) {
            touchHitCount += 1
          }
        }
      }
      stack.append(contentsOf: node.subviews)
    }
    let expectedHeight = KeyboardMetrics.totalHeight(
      actionBarVisible: self.actionBarVisible, kind: self.keyboardState.effectiveTypingKind
    )
    let probe = KeyboardLifecycleTrace.RenderProbe(
      checkpoint: checkpoint,
      expectedHeight: Self.traceDimension(expectedHeight),
      inputWidth: Self.traceDimension(input.bounds.width),
      inputHeight: Self.traceDimension(input.bounds.height),
      hostingWidth: Self.traceDimension(hosted?.bounds.width ?? 0),
      hostingHeight: Self.traceDimension(hosted?.bounds.height ?? 0),
      geometryWidth: Self.traceDimension(self.hostGeometry.size.width),
      geometryHeight: Self.traceDimension(self.hostGeometry.size.height),
      inputAlphaPercent: Self.traceAlpha(input.alpha),
      hostingAlphaPercent: Self.traceAlpha(hosted?.alpha ?? 0),
      inputHidden: input.isHidden,
      hostingHidden: hosted?.isHidden ?? true,
      hostingInWindow: hosted?.window != nil,
      hostingIntersectsInput: hosted != nil && input.bounds.intersects(hostingFrame),
      visitedSubviews: scanned,
      scanLimited: !stack.isEmpty,
      hostingLayerCount: hosted?.layer.sublayers?.count ?? 0,
      touchSurfaceCount: touchCount,
      touchSurfacesInWindow: touchInWindow,
      touchHitTestCount: touchHitCount,
      letterRowsExpected: self.keyboardState.expectsAlphabeticTouchRows
    )
    let missingRows = probe.letterRowsExpected && !probe.scanLimited
      && probe.hostingInWindow && probe.inputHeight >= 30
      && touchInWindow < 3
    // Detect stable host/SwiftUI height disagreements without rewriting the system constraints.
    let heightMismatch = probe.hostingInWindow && probe.inputHeight >= 30
      && (abs(probe.inputHeight - probe.expectedHeight) > 2
        || abs(probe.hostingHeight - probe.expectedHeight) > 2)
    let suspicious = !probe.hostingInWindow || probe.inputHidden
      || probe.hostingHidden || probe.inputAlphaPercent < 1
      || probe.hostingAlphaPercent < 1 || !probe.hostingIntersectsInput
      || probe.inputHeight < 30 || probe.hostingHeight < 30 || heightMismatch
      || (touchInWindow > 0 && touchHitCount == 0) || missingRows
    self.recordKeyboardTrace(
      suspicious ? .renderSuspicious : .renderCheckpoint, renderProbe: probe
    )
    // One bounded soft refresh; never replace the composition root.
    if missingRows && !self.missingRowsRefreshAttempted {
      self.missingRowsRefreshAttempted = true
      self.keyboardState.keyboardTouchRowsRecoveryRevision &+= 1
      hosted?.setNeedsLayout()
      hosted?.setNeedsDisplay()
      self.view.setNeedsLayout()
      self.recordKeyboardTrace(.renderRefreshRequested)
      self.scheduleRenderCheckpoint(checkpoint: "afterMissingRowsRefresh")
    }
    #endif
  }

  private static let automaticRecoveryWindow: TimeInterval = 90

  /// A completed dictation may outlive the keyboard process and the main
  /// app's mutable session token. Only the original UIKit field can regain
  /// automatic insertion; no host text or document identifier is persisted.
  private func recoverCompletedDictationDestination() {
    guard self.dictationRequestToken == nil else { return }
    let settings = SharedSettings()
    settings.synchronize()
    guard let delivery = TranscriptionBridge.readDelivery(
            maxAgeSeconds: Self.automaticRecoveryWindow
          ),
          TranscriptionBridge.cancellationToken() != delivery.sessionToken
    else { return }
    let document = self.availableDocumentIdentifier()
    let selected = !(self.textDocumentProxy.selectedText?.isEmpty ?? true)
    let sameDocument = DictationRequestPolicy.mayRecoverCompleted(
      requestedToken: self.dictationRequestToken,
      activeToken: settings.dictationSessionToken,
      deliveryToken: delivery.sessionToken,
      deliveryEpoch: delivery.destinationEpoch, currentDocument: document,
      fingerprint: settings.dictationDestinationFingerprint,
      recording: settings.isRecording,
      cancelled: settings.dictationCancellationRequested,
      hasSelection: selected
    )
    let sameDocumentlessHost = self.viewIfLoaded?.window != nil
      && DictationRequestPolicy.mayDeliverWithoutDocumentIdentifier(
        deliveryToken: delivery.sessionToken, requestedToken: nil,
        activeToken: settings.dictationSessionToken,
        deliveryEpoch: delivery.destinationEpoch, currentDocument: document,
        fingerprint: settings.dictationDestinationFingerprint,
        originProcessMarker: settings.dictationOriginProcessMarker,
        currentHost: self.hostProcess, recording: settings.isRecording,
        cancelled: settings.dictationCancellationRequested, hasSelection: selected
      )
    guard sameDocument || sameDocumentlessHost else { return }
    self.dictationRequestToken = delivery.sessionToken
    self.dictationDocumentID = document
    if let epoch = delivery.destinationEpoch {
      self.keyboardState.documentEpoch = epoch
    }
    FeatureDiagnostics.record(.bridge, .fallback,
      operationID: delivery.sessionToken, phase: .accepted)
  }

  func insertTranscribedText() {
    self.recoverCompletedDictationDestination()
    // Never use an unscoped latest result for automatic insertion or
    // display. A fresh keyboard must first recover its scoped request;
    // never select the newest unrelated transcript.
    let delivery = self.dictationRequestToken.flatMap { token in
      TranscriptionBridge.readDelivery(matching: token,
        destinationEpoch: self.keyboardState.documentEpoch)
        ?? TranscriptionBridge.readDelivery(matching: token, allowAnyDestination: true)
    }
    guard let delivery, !delivery.text.isEmpty else {
      DiagnosticLog.write("keyboard: NO TEXT available to insert")
      let settings = SharedSettings()
      settings.synchronize()
      if let outcome = settings.lastDictationOutcome {
        self.keyboardState.dictationOutcome = outcome
      }
      return
    }
    let text = delivery.text
    let settings = SharedSettings()
    settings.synchronize()
    let currentDocument = self.availableDocumentIdentifier()
    let matchesDocument = delivery.canInsert(
      requestToken: self.dictationRequestToken,
      currentEpoch: self.keyboardState.documentEpoch
    ) && self.dictationDocumentID != nil
      && currentDocument == self.dictationDocumentID
      && DictationRequestPolicy.isSameDestination(
        sessionToken: self.dictationRequestToken, document: currentDocument,
        fingerprint: settings.dictationDestinationFingerprint
      )
    // Some UIKit hosts return no document UUID. In that case accept only
    // a recent completed request from this exact originating host process.
    let matchesDocumentlessHost = self.viewIfLoaded?.window != nil
      && DictationRequestPolicy.mayDeliverWithoutDocumentIdentifier(
        deliveryToken: delivery.sessionToken,
        requestedToken: self.dictationRequestToken,
        activeToken: settings.dictationSessionToken,
        deliveryEpoch: delivery.destinationEpoch, currentDocument: currentDocument,
        fingerprint: settings.dictationDestinationFingerprint,
        originProcessMarker: settings.dictationOriginProcessMarker,
        currentHost: self.hostProcess, recording: settings.isRecording,
        cancelled: settings.dictationCancellationRequested,
        hasSelection: !(self.textDocumentProxy.selectedText?.isEmpty ?? true)
      )
    guard !settings.dictationCancellationRequested,
          (matchesDocument || matchesDocumentlessHost) else {
      // Keep the pending delivery in the outbox and in History. A new keyboard
      // can stop capture, but may not write into an unverified host field.
      let reason: FeatureDiagnostics.FailureReason = currentDocument == nil
        ? .destinationUnavailable
        : (self.dictationDocumentID == nil ? .destinationOwnerLost : .destinationChanged)
      FeatureDiagnostics.record(.bridge, .rejected,
        failureReason: reason,
        operationID: delivery.sessionToken, phase: .rejected)
      return
    }
    FeatureDiagnostics.record(.bridge, .started)
    self.keyboardState.dictationOutcome = nil
    if !self.isPerformingHistoryNavigation {
      self.keyboardState.clearLLMHistory()
    }

    let blockedLiveEdit = self.liveTranscriptionBlockedToken == delivery.sessionToken
      || Self.blockedLiveSessionToken == delivery.sessionToken
    if blockedLiveEdit {
      self.abandonExperimentalLiveOwnership()
      Self.blockedLiveSessionToken = nil
      self.liveTranscriptionBlockedToken = nil
      if !matchesDocumentlessHost {
        FeatureDiagnostics.record(.bridge, .fallback)
        return
      }
    }
    // A documentless return has no live-edit anchor to reconcile. After
    // verifying the original host process, use the ordinary insertion path.
    if !matchesDocumentlessHost {
      switch self.completeExperimentalLiveText(
        delivery, cancellationRequested: settings.dictationCancellationRequested
      ) {
      case .inserted:
        TranscriptionBridge.acknowledgeDelivery(delivery.resultID)
        self.keyboardState.showFinalOutputPreview(text)
        FeatureDiagnostics.record(.bridge, .completed)
        return
      case .review:
        FeatureDiagnostics.record(.bridge, .fallback)
        return
      case .notApplicable:
        break
      }
    }
    if self.autoApplyLLMIfNeeded(directText: text) {
      // The existing keyboard LLM bridge now owns the pending output.
      TranscriptionBridge.acknowledgeDelivery(delivery.resultID)
      FeatureDiagnostics.record(.bridge, .queued)
      return
    }

    DiagnosticLog.write("keyboard: inserting \(text.count) chars into textDocumentProxy")
    self.insertSpacedText(text)
    TranscriptionBridge.acknowledgeDelivery(delivery.resultID)
    FeatureDiagnostics.record(.bridge, .completed)
    self.keyboardState.showFinalOutputPreview(text)
  }

  func pingMainAppForSessionStatus() {
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.requestSessionStatus)
  }

  private static let staleFallbackTimeout: TimeInterval = 2.0

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
  private let hostGeometry = KeyboardHostGeometry()
  private var staleFallbackTimer: Timer?
  private var warmStartSessionAcknowledged = false
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

  private func setupInputModeObserver() {
    #if !APPSTORE
    NotificationCenter.default.addObserver(
      self, selector: #selector(inputModeDidChange),
      name: UITextInputMode.currentInputModeDidChangeNotification,
      object: nil
    )
    #endif
  }

  @objc private func inputModeDidChange() {
    guard self.viewIfLoaded?.window != nil else { return }
    self.lastObservedDocumentInputModeLanguage = self.textDocumentProxy.documentInputMode?.primaryLanguage
    self.recordKeyboardTrace(.inputModeChanged)
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
    self.pingValidator.startIfNeeded(for: self.keyboardState)
    self.pingMainAppForSessionStatus()
    self.keyboardState.appearedAt = CFAbsoluteTimeGetCurrent()
    self.resumeProcessingTimeoutIfNeeded()
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
        let settings = SharedSettings()
        settings.synchronize()
        guard settings.isRecording,
              settings.dictationSessionToken == vc.dictationRequestToken else { return }
        // Stop can be requested before the capture acknowledgment arrives.
        // Do not reactivate the recording UI during finalization.
        guard !vc.keyboardState.isProcessing else { return }
        vc.staleFallbackTimer?.invalidate()
        vc.staleFallbackTimer = nil
        vc.pingValidator.cancel()
        vc.cancelProcessingTimeout()
        vc.keyboardState.isProcessing = false
        vc.keyboardState.voiceProcessingProgress = nil
        vc.keyboardState.clearFinalOutputPreview()
        vc.keyboardState.liveSourcePreview = nil
        vc.keyboardState.isRecording = true
        // A capture acknowledgment is stronger than an idle session ping.
        vc.warmStartSessionAcknowledged = true
        // A delayed start callback cannot restore this same blocked session.
        if vc.liveTranscriptionBlockedToken != settings.dictationSessionToken {
          vc.liveTranscriptionBlockedToken = nil
        }
        if Self.blockedLiveSessionToken != settings.dictationSessionToken {
          Self.blockedLiveSessionToken = nil
        }
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
        guard !SharedSettings().isRecording else { return }
        vc.cancelProcessingTimeout()
        vc.staleFallbackTimer?.invalidate()
        vc.staleFallbackTimer = nil
        vc.keyboardState.stopLevelPolling()
        vc.keyboardState.liveSourcePreview = nil
        vc.keyboardState.isRecording = false
        vc.keyboardState.recordingStartedAt = 0
        vc.keyboardState.isStartingRecording = false
        vc.keyboardState.syncModelLoading()
        vc.keyboardState.syncDictationLock()
        vc.insertTranscribedText()
        if vc.liveTranscriptionDocumentID != nil,
           (SharedSettings().dictationCancellationRequested
             || (TranscriptionBridge.readDelivery(matching: vc.dictationRequestToken,
                 destinationEpoch: vc.keyboardState.documentEpoch)?.text ?? "").isEmpty) {
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

  func prepareDictationDestination() {
    let settings = SharedSettings()
    self.dictationRequestToken = settings.dictationSessionToken
    self.dictationDocumentID = self.availableDocumentIdentifier()
    settings.dictationDestinationEpoch = self.dictationDocumentID == nil
      ? nil : self.keyboardState.documentEpoch
    settings.dictationDestinationFingerprint = DictationRequestPolicy.destinationFingerprint(
      sessionToken: self.dictationRequestToken, document: self.dictationDocumentID
    )
    settings.dictationOriginProcessMarker = DictationRequestPolicy.originProcessMarker(
      token: self.dictationRequestToken, process: self.hostProcess
    )
    settings.synchronize()
  }

  /// Restore capture control after iOS recreates the keyboard extension.
  /// Only a matching request-bound field fingerprint restores text ownership.
  /// A different field may still stop/cancel, but receives preview-only output.
  func recoverActiveDictationAfterReentry() {
    let settings = SharedSettings()
    settings.synchronize()
    guard !settings.dictationCancellationRequested,
          (settings.isRecording || settings.isKeyboardRequestRecent()),
          let token = settings.dictationSessionToken,
          UUID(uuidString: token) != nil else { return }
    let document = self.availableDocumentIdentifier()
    let sameField = DictationRequestPolicy.isSameDestination(
      sessionToken: token, document: document,
      fingerprint: settings.dictationDestinationFingerprint
    )
    if self.dictationRequestToken == token,
       self.dictationDocumentID == document, sameField,
       self.keyboardState.documentEpoch == settings.dictationDestinationEpoch {
      return
    }
    self.dictationRequestToken = token
    if sameField, let epoch = settings.dictationDestinationEpoch {
      self.dictationDocumentID = document
      self.keyboardState.documentEpoch = epoch
      // A recreated controller may resume live text only for the exact
      // same request and UIKit destination. Never clear a foreign tombstone.
      if self.liveTranscriptionBlockedToken == token {
        self.liveTranscriptionBlockedToken = nil
      }
      if Self.blockedLiveSessionToken == token {
        Self.blockedLiveSessionToken = nil
      }
    } else {
      self.dictationDocumentID = nil
      self.liveTranscriptionBlockedToken = token
      Self.blockedLiveSessionToken = token
      FeatureDiagnostics.record(.bridge, .fallback, operationID: token)
    }
    self.keyboardState.isSessionActive = settings.isSessionActive
    self.keyboardState.isRecording = settings.isRecording
    self.keyboardState.isStartingRecording = !settings.isRecording
    self.keyboardState.recordingStartedAt = settings.recordingStartedAt
  }

  private func startDictationViaDarwin() {
    let settings = SharedSettings()
    settings.synchronize()
    // A recreated keyboard must not rearm a capture that is already running.
    if settings.isRecording && settings.isSessionActive
        && !settings.dictationCancellationRequested,
       let token = settings.dictationSessionToken,
       UUID(uuidString: token) != nil {
      FeatureDiagnostics.record(.speech, .selected, operationID: token)
      self.recoverActiveDictationAfterReentry()
      self.pingMainAppForSessionStatus()
      return
    }
    guard !self.keyboardState.isProcessing, !self.keyboardState.isRecording,
          !self.keyboardState.isStartingRecording else { return }
    self.saveHostBundleId()
    self.keyboardState.isStartingRecording = true
    let token = UUID().uuidString
    // A blocked previous session must not suppress a fresh request.
    self.liveTranscriptionBlockedToken = nil
    Self.blockedLiveSessionToken = nil
    self.abandonExperimentalLiveOwnership()
    settings.dictationSessionToken = token
    LiveDictationLatency.begin(token: token)
    self.prepareDictationDestination()
    settings.dictationCancellationRequested = false
    settings.synchronize()
    self.warmStartSessionAcknowledged = false
    self.staleFallbackTimer?.invalidate()
    self.staleFallbackTimer = nil
    let direct = DictationRequestPolicy.shouldRequestWarmSession(
      keyboardActive: self.keyboardState.isSessionActive,
      appActive: settings.isSessionActive,
      heartbeat: settings.mainAppHeartbeat,
      now: CFAbsoluteTimeGetCurrent(),
      practiceFocused: HistoryKeyboardTestSession.isFocused
    )
    if direct {
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.requestStartDictation)
      self.pingMainAppForSessionStatus()
      self.scheduleWarmStartCheck(token: token, retryCount: 0)
    } else {
      // Cold activation opens the app with the SAME token and destination.
      // Only the controller creates a request; the mic view never rearms.
      FeatureDiagnostics.record(.speech, .fallback,
        failureReason: .coldAudioSessionStart, operationID: token)
      self.openDictateDeepLinkFallback(reason: "cold audio session")
    }
  }

  private func scheduleWarmStartCheck(token: String, retryCount: Int) {
    self.staleFallbackTimer?.invalidate()
    guard !HistoryKeyboardTestSession.isFocused else { return }
    self.staleFallbackTimer = Timer.scheduledTimer(
      withTimeInterval: Self.staleFallbackTimeout, repeats: false
    ) { [weak self] _ in
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.staleFallbackTimer = nil
        let settings = SharedSettings()
        settings.synchronize()
        let now = CFAbsoluteTimeGetCurrent()
        guard DictationRequestPolicy.isCurrent(
          started: token, current: settings.dictationSessionToken,
          cancelled: settings.dictationCancellationRequested
        ), self.viewIfLoaded?.window != nil, !self.keyboardState.isRecording else { return }

        let audioAlive = settings.isSessionActive
          && DictationRequestPolicy.hasRecentAudioHeartbeat(
            settings.mainAppHeartbeat, now: now
          )
        if (audioAlive || settings.isSessionActive) && retryCount == 0 {
          // Replay a lost Darwin notification once with the same request token.
          FeatureDiagnostics.record(.speech, .fallback)
          DiagnosticLog.write("keyboard: retrying warm dictation request")
          TranscriptionBridge.postDarwinNotification(DarwinNotificationName.requestStartDictation)
          self.scheduleWarmStartCheck(token: token, retryCount: 1)
          return
        }
        if DictationRequestPolicy.shouldOpenColdFallback(
          requestToken: token, currentToken: settings.dictationSessionToken,
          cancelled: settings.dictationCancellationRequested,
          keyboardVisible: true, recording: self.keyboardState.isRecording,
          appAcknowledged: self.warmStartSessionAcknowledged,
          heartbeat: settings.mainAppHeartbeat, now: now
        ) {
          FeatureDiagnostics.record(.speech, .fallback,
            failureReason: .warmStartUnacknowledged, operationID: token)
          self.openDictateDeepLinkFallback(reason: "no active audio engine")
          return
        }
        self.keyboardState.isStartingRecording = false
        FeatureDiagnostics.record(.speech, .failed)
        DiagnosticLog.write("keyboard: warm dictation not acknowledged; stayed in host")
      }
    }
  }

  private func openDictateDeepLinkFallback(reason _: String) {
    let settings = SharedSettings()
    // The keyboard does not own the app's audio-session state.
    settings.keyboardRequestedDictationAt = CFAbsoluteTimeGetCurrent()
    settings.keyboardRequestedDictation = true
    if settings.dictationSessionToken == nil {
      settings.dictationSessionToken = UUID().uuidString
    }
    settings.synchronize()
    // Only the containing app may set the actual session state.
    self.keyboardState.isStartingRecording = true
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
    if self.dictationRequestToken == nil { self.recoverActiveDictationAfterReentry() }
    self.cancelExperimentalLiveText()
    self.keyboardState.liveSourcePreview = nil
    self.staleFallbackTimer?.invalidate()
    self.staleFallbackTimer = nil
    self.warmStartSessionAcknowledged = false
    self.cancelProcessingTimeout()
    self.keyboardState.isStartingRecording = false
    self.keyboardState.isRecording = false
    self.keyboardState.recordingStartedAt = 0
    self.keyboardState.isProcessing = false
    self.keyboardState.stopLevelPolling()
    let settings = SharedSettings()
    let cancelled = self.dictationRequestToken
    TranscriptionBridge.requestCancellation(for: cancelled)
    if OperationPolicy.ownsCancellation(requested: cancelled, active: settings.dictationSessionToken) {
      settings.keyboardRequestedDictation = false
      settings.dictationCancellationRequested = true
      settings.dictationDestinationEpoch = nil
      settings.dictationDestinationFingerprint = nil
      settings.dictationOriginProcessMarker = nil
      settings.synchronize()
    }
    self.dictationRequestToken = nil
    self.dictationDocumentID = nil
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.requestCancelDictation)
  }

  func stopDictationViaDarwin() {
    if self.dictationRequestToken == nil { self.recoverActiveDictationAfterReentry() }
    self.staleFallbackTimer?.invalidate()
    self.staleFallbackTimer = nil
    self.saveHostBundleId()
    // A Stop request ends the microphone interaction immediately; the host
    // retains ownership of audio capture and reports the final result later.
    self.keyboardState.isRecording = false
    self.keyboardState.isStartingRecording = false
    self.keyboardState.recordingStartedAt = 0
    self.keyboardState.isProcessing = true
    self.keyboardState.syncVoiceProcessingProgress()
    self.keyboardState.syncModelLoading()
    self.keyboardState.stopLevelPolling()
    TranscriptionBridge.requestStop(for: self.dictationRequestToken)
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
        // Audio-session existence alone is not a recording-start acknowledgment.
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
        vc.warmStartSessionAcknowledged = false
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
    let proxy = self.makeKeyboardProxy()
    let keyboardView = KeyboardView(proxy: proxy, keyboardState: self.keyboardState)
    let hosting = UIHostingController(rootView: keyboardView)
    hosting.safeAreaRegions = []
    hosting.view.backgroundColor = .clear
    hosting.view.isOpaque = false
    hosting.view.translatesAutoresizingMaskIntoConstraints = false

    self.addChild(hosting)
    self.view.addSubview(hosting.view)
    hosting.didMove(toParent: self)

    let kind = self.keyboardState.effectiveTypingKind
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
    #if !APPSTORE
    if let hud = self.liveDebugHUD { self.view.bringSubviewToFront(hud) }
    #endif
    self.recordKeyboardTrace(.hostingMounted)
  }

  private func applyKeyboardHeight() {
    let target = KeyboardMetrics.totalHeight(
      actionBarVisible: self.actionBarVisible,
      kind: self.keyboardState.effectiveTypingKind
    )
    let outerNeedsUpdate = self.heightConstraint.map { $0.constant != target } ?? false
    let hostingNeedsUpdate = self.hostingHeightConstraint.map { $0.constant != target } ?? false
    guard outerNeedsUpdate || hostingNeedsUpdate else { return }
    self.heightConstraint?.constant = target
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
        self?.refreshHostInputTraits()
        #if !APPSTORE
        self?.recordLiveDebugAction(.textCommitted)
        #endif
      },
      documentContextBeforeInput: { [weak self] in
        self?.textDocumentProxy.documentContextBeforeInput
      },
      insertSpace: { [weak self] in
        self?.insertSpace()
        self?.refreshHostInputTraits()
        #if !APPSTORE
        self?.recordLiveDebugAction(.spaceCommitted)
        #endif
      },
      deleteBackward: { [weak self] in
        self?.previousSpaceTap = nil
        // Only an actual Delete keypress is evidence of a touch repair.
        // Candidate replacements also call this proxy and must not teach hitboxes.
        self?.textDocumentProxy.deleteBackward()
        self?.refreshHostInputTraits()
        #if !APPSTORE
        self?.recordLiveDebugAction(.deleteBackward)
        #endif
      },
      deleteWordBackward: { [weak self] in
        KeyboardTouchLearning.shared.invalidate()
        self?.deletePreviousWord()
        self?.refreshHostInputTraits()
        #if !APPSTORE
        self?.recordLiveDebugAction(.deleteWord)
        #endif
      },
      deleteAll: { [weak self] in
        self?.previousSpaceTap = nil
        self?.deleteAllText()
        self?.refreshHostInputTraits()
        #if !APPSTORE
        self?.recordLiveDebugAction(.deleteAll)
        #endif
      },
      advanceToNextInputMode: { [weak self] in
        #if !APPSTORE
        self?.recordLiveDebugAction(.nextKeyboardRequested)
        #endif
        self?.advanceToNextInputMode()
      },
      openURL: { [weak self] url in
        if url.host == DeepLink.dictateHost { self?.prepareDictationDestination() }
        self?.openURL(url)
      },
      startDictation: { [weak self] in
        #if !APPSTORE
        self?.recordLiveDebugAction(.micStart)
        #endif
        self?.startDictationViaDarwin()
      },
      stopDictation: { [weak self] in
        #if !APPSTORE
        self?.recordLiveDebugAction(.micStop)
        #endif
        self?.stopDictationViaDarwin()
      },
      cancelDictation: { [weak self] in
        #if !APPSTORE
        self?.recordLiveDebugAction(.micCancel)
        #endif
        self?.cancelDictationViaDarwin()
      },
      resolveHost: { [weak self] in
        self?.saveHostBundleId()
      },
      requestLLMProcessing: { [weak self] action, customPromptId in
        #if !APPSTORE
        self?.recordLiveDebugAction(.aiRequest)
        #endif
        self?.requestLLMProcessing(action: action, customPromptId: customPromptId)
      },
      requestLLMClipboard: { [weak self] in
        self?.requestLLMClipboardProcessing()
      },
      adjustTextPosition: { [weak self] offset in
        #if !APPSTORE
        self?.recordLiveDebugAction(.cursorMove)
        #endif
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
    #if !APPSTORE
    let modeLanguage = self.textDocumentProxy.documentInputMode?.primaryLanguage
    if modeLanguage != self.lastObservedDocumentInputModeLanguage {
      self.lastObservedDocumentInputModeLanguage = modeLanguage
      self.recordKeyboardTrace(.inputModeChanged)
    }
    #endif
    let currentDocument = self.availableDocumentIdentifier()
    let sameDocument = KeyboardDocumentIdentifier.isSameOrUnavailable(
      current: currentDocument, previous: self.lastTouchDocumentID
    )
    if currentDocument == nil {
      // Stop associating touch/cursor state with a host whose identity is unknown.
      // Do this once per transition, not on every keyboard text callback.
      if self.lastTouchDocumentID != nil {
        KeyboardTouchLearning.shared.invalidate()
        self.resetCursorVerticalState()
        self.lastTouchDocumentID = nil
        self.keyboardState.documentEpoch = UUID()
      }
    } else if !sameDocument {
      self.keyboardState.documentEpoch = UUID()
      KeyboardTouchLearning.shared.invalidate()
      self.resetCursorVerticalState()
      self.lastTouchDocumentID = currentDocument
      // A host can switch fields without another appearance callback.
      self.keyboardState.keyboardAppearanceRevision &+= 1
      self.missingRowsRefreshAttempted = false
      self.view.setNeedsLayout()
      self.recordKeyboardTrace(.documentChanged)
      self.scheduleRenderCheckpoint(checkpoint: "afterDocumentChange")
    }
    let previousHostHasText = self.lastObservedHostHasText
    let currentHostHasText = self.textDocumentProxy.hasText
    self.lastObservedHostHasText = currentHostHasText
    let hadHostText = self.keyboardState.hostInputTraits.hasText
    self.refreshHostInputTraits()
    if sameDocument && ((previousHostHasText == true && !currentHostHasText)
        || (hadHostText && !self.keyboardState.hostInputTraits.hasText)) {
      // A cleared compose field is a possible Send transition. Only store
      // Boolean state; never retain host text or document identifiers.
      self.keyboardState.keyboardAppearanceRevision &+= 1
      self.missingRowsRefreshAttempted = false
      self.recordKeyboardTrace(.hostTextCleared)
      self.scheduleRenderCheckpoint(checkpoint: "afterHostTextCleared")
    }
    self.keyboardState.textContextRevision &+= 1
    self.syncInputModeSwitchKey()
    self.insertDeferredAppearanceText()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    self.insertDeferredAppearanceText()
    self.recordKeyboardTrace(.didAppear)
    self.startMemoryWatch()
    self.scheduleRenderCheckpoint(checkpoint: "afterAppear")
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    self.stopMemoryWatch()
    self.recordKeyboardTrace(.didDisappear)
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let width = self.view.bounds.width
    let height = self.view.bounds.height
    // Actual UIKit bounds, not the height Altboard requested from Auto Layout.
    self.hostGeometry.update(width: width, height: height)
    let hostValid = self.hostGeometry.size.width > 1 && self.hostGeometry.size.height > 1
    let inWindow = self.hostingController?.viewIfLoaded?.window != nil
    let signature = "\(width.isFinite ? Int(width.rounded()) : -1):\(height.isFinite ? Int(height.rounded()) : -1):\(hostValid):\(inWindow)"
    if self.lastTracedLayoutKey != signature {
      self.lastTracedLayoutKey = signature
      self.recordKeyboardTrace(.layoutChanged)
    }
  }

  /// UIKit can transiently return nil for this Objective-C UUID property.
  /// Never access the Swift-imported nonoptional documentIdentifier directly.
  /// This method does not log or persist the actual identifier.
  func availableDocumentIdentifier() -> UUID? {
    let identifier = KeyboardDocumentIdentifier.read(from: self.textDocumentProxy)
    if identifier == nil {
      if !self.documentIdentifierUnavailableReported {
        self.documentIdentifierUnavailableReported = true
        self.recordKeyboardTrace(.documentIdentifierUnavailable)
      }
    } else if self.documentIdentifierUnavailableReported {
      self.documentIdentifierUnavailableReported = false
      self.recordKeyboardTrace(.documentIdentifierRecovered)
    }
    return identifier
  }

  private func refreshHostInputTraits() {
    let proxy = self.textDocumentProxy
    let traits = KeyboardHostInputTraits(
      keyboardType: proxy.keyboardType ?? .default,
      returnKeyType: proxy.returnKeyType ?? .default,
      contentType: proxy.textContentType?.rawValue,
      autocapitalizationType: proxy.autocapitalizationType ?? .sentences,
      autocorrectionType: proxy.autocorrectionType ?? .default,
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




