import Foundation
import UIKit

import QuartzCore
import SwiftUI

@MainActor
final class KeyboardState: ObservableObject {

  @Published var isRecording = false
  @Published var recordingStartedAt: TimeInterval = 0
  @Published var isStartingRecording = false
  @Published var isProcessing = false
  @Published var isSessionActive = false
  @Published var isModelLoading = false
  @Published var hasPreparedModelOnce = false
  @Published var hasUsableModel = false
  @Published var parakeetV3NeedsRedownload = false
  @Published var isMicrophoneAuthorized = false
  @Published var hasFullAccess = false
  @Published var useCustomSpaceBar = false
  @Published var showSettingsKey = true
  @Published var showGlobeKey = false
  @Published var showOutputLanguageButton = true
  @Published var showAIButton = true
  @Published var isTranslationMode = false
  @Published var selectedVariantSupportsTranslation = false
  @Published var selectedVariantSpecializesForNeuralEngine = false
  @Published var audioLevel: Float = 0
  @Published var recentAudioLevels = [Float](repeating: 0, count: 17)
  @Published var isLowDiskSpace = false
  @Published var hasUsableLLMModel = false
  @Published var isLLMProcessing = false
  @Published var llmEnabled = false
  @Published var llmCustomPrompts = [LLMCustomPrompt]()
  @Published var defaultLLMActionSelection = LLMActionSelection.none
  @Published var longPressLLMAction = LLMActionSelection.none
  @Published var disabledLLMActions = Set<LLMAction>()
  @Published var llmTextHistory = [String]()
  @Published var llmHistoryIndex = -1
  var llmHistorySuffix = ""
  @Published var showLLMActions = false
  @Published var llmError: LLMError?
  @Published var dictationOutcome: DictationOutcome?
  @Published var finalOutputPreview: String?
  private var finalPreviewGeneration = UUID()
  @Published var voiceProcessingProgress: VoiceProcessingProgress?
  @Published var needsInputModeSwitchKey = false
  @Published var keyboardHapticsEnabled = true
  @Published var textContextRevision = 0
  @Published var keyboardAppearanceRevision = 0
  // Render-only expectation; does not store host text or touch coordinates.
  var expectsAlphabeticTouchRows = false
  @Published var hostInputTraits = KeyboardHostInputTraits()
  @Published var keyboardKind = KeyboardKind.standard
  @Published var isDictationLocked = false
  @Published var showsMicHint = false


  var openURLAction: ((URL) -> Void)?

  /// Installed by UIInputViewController; configure the real UIKit globe key
  /// with Apple's handleInputModeList(from:with:) on all touch events.
  /// The callback captures the controller weakly to avoid a retain cycle.
  var configureInputModeListButton: ((UIButton) -> Void)?

  var appearedAt: CFAbsoluteTime = 0

  /// Keep typing controls visible while recording in every non-mic mode.
  // A third-party keyboard must retain ordinary typing without microphone,
  // Full Access, a downloaded model, or writable App Group storage.
  var requiresBasicTypingFallback: Bool {
    self.keyboardKind != .alphabetic &&
      (!self.hasFullAccess || !self.isMicrophoneAuthorized ||
       !self.hasUsableModel || AppGroup.containerURL == nil)
  }

  var effectiveTypingKind: KeyboardKind {
    self.requiresBasicTypingFallback ? .alphabetic : self.keyboardKind
  }

  var auxiliaryControlsHidden: Bool {
    self.keyboardKind == .standard
      && (self.isStartingRecording || self.isRecording || self.isProcessing)
  }

  var canUndoLLM: Bool {
    self.llmHistoryIndex > 0
  }

  var canRedoLLM: Bool {
    self.llmHistoryIndex >= 0 && self.llmHistoryIndex < self.llmTextHistory.count - 1
  }

  var hasLLMHistory: Bool {
    self.llmTextHistory.count > 1
  }

  /// A small final result preview remains in the existing control row for
  /// five seconds, without changing the host application's input field.
  func showFinalOutputPreview(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let generation = UUID()
    self.finalPreviewGeneration = generation
    self.finalOutputPreview = String(trimmed.prefix(100))
    Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(5)) } catch { return }
      guard let self, self.finalPreviewGeneration == generation else { return }
      self.finalOutputPreview = nil
    }
  }

  func clearFinalOutputPreview() {
    self.finalPreviewGeneration = UUID()
    self.finalOutputPreview = nil
  }

  func clearLLMHistory() {
    self.llmTextHistory = []
    self.llmHistoryIndex = -1
    self.llmHistorySuffix = ""
  }

  func bootstrapLayoutSettings() {
    self.settings.synchronize()
    self.keyboardKind = self.settings.keyboardKind
    self.keyboardHapticsEnabled = self.settings.keyboardHapticsEnabled
  }

  func refresh() {
    self.settings.synchronize()
    self.isStartingRecording = false
    self.isRecording = self.settings.isRecording
    self.recordingStartedAt = self.settings.recordingStartedAt
    self.isSessionActive = self.settings.isSessionActive
    if self.isRecording, !self.isSessionActive {
      self.isRecording = false
      self.settings.isRecording = false
    }
    self.isProcessing = false
    self.voiceProcessingProgress = nil
    self.syncVoiceProcessingProgress()
    self.isModelLoading = self.settings.isModelLoading
    self.hasPreparedModelOnce = self.settings.hasPreparedModelOnce
    self.hasUsableModel = self.settings.hasUsableModel
    self.parakeetV3NeedsRedownload = self.settings.parakeetV3NeedsRedownload
    self.isMicrophoneAuthorized = self.settings.isMicrophoneAuthorized
    self.useCustomSpaceBar = self.settings.useCustomSpaceBar
    self.showSettingsKey = self.settings.keyboardShowSettingsKey
    self.showGlobeKey = self.settings.keyboardShowGlobeKey
    self.showOutputLanguageButton = self.settings.keyboardShowOutputLanguageButton
    self.showAIButton = self.settings.keyboardShowAIButton
      && self.settings.llmEnabled && self.settings.hasUsableLLMModel
    self.keyboardKind = self.settings.keyboardKind
    let selectedVariant = self.settings.selectedVariant
    self.selectedVariantSupportsTranslation = selectedVariant.supportsTranslation
    self.selectedVariantSpecializesForNeuralEngine = selectedVariant.specializesForNeuralEngine()
    if !selectedVariant.supportsTranslation {
      self.isTranslationMode = false
      self.settings.isTranslationMode = false
    }
    self.hasUsableLLMModel = self.settings.hasUsableLLMModel
    self.isLLMProcessing = self.settings.isLLMProcessing
    self.llmEnabled = self.settings.llmEnabled
    self.llmCustomPrompts = self.settings.llmCustomPrompts
    self.defaultLLMActionSelection = self.settings.defaultLLMActionSelection
    self.longPressLLMAction = self.settings.longPressLLMAction
    self.disabledLLMActions = self.settings.disabledLLMActions
    self.needsInputModeSwitchKey = self.settings.needsInputModeSwitchKey
    self.keyboardHapticsEnabled = self.settings.keyboardHapticsEnabled
    self.syncDictationLock()
    self.checkDiskSpace()
  }

  /// Refresh the main app's local progress file, including when the keyboard
  /// reappears midway through a slow ASR/translation operation.
  func syncVoiceProcessingProgress() {
    self.settings.synchronize()
    guard let update = TranscriptionBridge.readVoiceProgress(),
          update.sessionToken != nil,
          update.sessionToken == self.settings.dictationSessionToken,
          Date().timeIntervalSinceReferenceDate - update.updatedAt < 180
    else {
      self.voiceProcessingProgress = nil
      return
    }
    self.voiceProcessingProgress = update
    if !self.isRecording {
      self.isProcessing = true
    }
  }

  func syncModelLoading() {
    self.settings.synchronize()
    self.isModelLoading = self.settings.isModelLoading
    self.hasPreparedModelOnce = self.settings.hasPreparedModelOnce
  }

  func syncDictationLock() {
    self.settings.synchronize()
    self.isDictationLocked = self.settings.isDictationLocked
    if self.isDictationLocked {
      self.showLLMActions = false
    }
  }

  func syncOnboardingPractice(hostProcessID: Int?) {
    self.showsMicHint = self.settings.showsMicHint(hostProcessID: hostProcessID)
    if self.settings.isOnboardingPracticeHost(hostProcessID) {
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.keyboardShownInPractice)
    }
  }

  func dismissMicHint() {
    guard self.showsMicHint else { return }
    withAnimation(.easeOut(duration: 0.2)) {
      self.showsMicHint = false
    }
    self.settings.isMicHintDismissed = true
  }

  func toggleTranslationMode() {
    self.isTranslationMode.toggle()
    self.settings.isTranslationMode = self.isTranslationMode
  }

  func startLevelPolling() {
    guard self.displayLink == nil else { return }
    self.recentAudioLevels = [Float](repeating: 0, count: 17)
    let target = DisplayLinkTarget { [weak self] in
      guard let self else { return false }
      self.pollAudioLevel()
      return true
    }
    let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 20, preferred: 20)
    link.add(to: .main, forMode: .common)
    target.link = link
    self.displayLinkTarget = target
    self.displayLink = link
  }

  func stopLevelPolling() {
    self.displayLink?.invalidate()
    self.displayLink = nil
    self.displayLinkTarget = nil
    self.audioLevel = 0
    self.recentAudioLevels = [Float](repeating: 0, count: 17)
  }

  private let settings = SharedSettings()
  private let levelBridge = AudioLevelBridge(mode: .reader)
  private var displayLink: CADisplayLink?
  private var displayLinkTarget: DisplayLinkTarget?
  private func checkDiskSpace() {
    self.isLowDiskSpace = DiskSpace.isLow()
  }

  private func pollAudioLevel() {
    // Scrolling levels come from the microphone RMS tap, never a fake sine.
    let level = max(0, min(1, self.levelBridge.readLevel()))
    self.audioLevel = level
    self.recentAudioLevels.removeFirst()
    self.recentAudioLevels.append(level)
  }

}

private final class DisplayLinkTarget: NSObject {

  init(callback: @escaping () -> Bool) {
    self.callback = callback
  }

  weak var link: CADisplayLink?

  @objc
  func tick() {
    if !self.callback() {
      self.link?.invalidate()
    }
  }

  private let callback: () -> Bool
}

