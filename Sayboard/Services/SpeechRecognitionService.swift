import AVFoundation
import Combine
import FluidAudio

import SwiftUI
import UIKit
import Darwin

@MainActor
protocol ModelLoading: AnyObject {
  var isModelInUse: Bool { get }
  func loadModel(variant: ModelVariant, from url: URL) async -> Bool
}

@MainActor
final class SpeechRecognitionService: ObservableObject {

  init() {
    self.setupDarwinObservers()
    self.setupSessionCallbacks()
    self.forwardSessionState()
  }

  static let maxRecordingDuration: TimeInterval = 30 * 60

  @Published var isRecording = false
  @Published var isSessionActive = false
  @Published var historySaveGeneration = 0

  let session = BackgroundAudioSession()
  let whisperService = WhisperKitTranscriptionService()
  let parakeetService = ParakeetTranscriptionService()
  let moonshineService = MoonshineTranscriptionService()
  let qwen3Service = Qwen3TranscriptionService()
  let qwenHKService = HKCantoneseGGUFTranscriptionService()
  let senseVoiceService = SenseVoiceTranscriptionService()
  weak var downloadService: ModelDownloadService?
  weak var llmCoordinator: LLMProcessingCoordinator?

  let settings = SharedSettings()
  let accumulator = AudioBufferAccumulator()
  let audioRecorder = AudioRecorder()
  private(set) var activeDictationToken: String?
  private(set) var speechWorkers = 0
  private var modelLoadsInFlight = 0
  private var finalizationTask: Task<Void, Never>?
  private var captureConfirmationTask: Task<Void, Never>?

  var canBeginTextWork: Bool {
    OperationPolicy.canBeginTextWork(
      capturing: self.session.captureOwner != nil || self.isRecording,
      speechWorkers: self.speechWorkers + self.modelLoadsInFlight
    )
  }

  var isModelInUse: Bool {
    self.isRecording || self.isStopping || self.speechWorkers > 0 || self.modelLoadsInFlight > 0
      || self.llmCoordinator?.isProcessing == true
      || MeetingRecordingCoordinator.shared.isRecording
      || MeetingRecordingCoordinator.shared.isFinalizing
      || MeetingRecordingCoordinator.shared.translatingRecordID != nil
      || ConversationCoordinator.shared.recordingSide != nil
      || ConversationCoordinator.shared.processing
  }

  var currentTranscription = ""
  @Published var currentRawTranscription = ""
  var recordingSpokenLanguages = [String]()
  var experimentalLiveTask: Task<Void, Never>?
  @Published var liveDictationStatus = "Idle"
  var currentAudioFileName: String?
  var currentWordBoundaries: (start: Float, end: Float)?

  @Published private(set) var isStopping = false

  var activeLoadState: ModelLoadState {
    switch self.settings.selectedVariant.engine {
    case .whisperKit: self.whisperService.loadState
    case .parakeet: self.parakeetService.loadState
    case .moonshine: self.moonshineService.loadState
    case .qwen3:
      self.settings.selectedVariant == .qwen3ASR17BCantoneseHK
        ? self.qwenHKService.loadState : self.qwen3Service.loadState
    case .senseVoice: self.senseVoiceService.loadState
    }
  }

  func startRecording() {
    guard self.activeLoadState == .loaded else {
      self.rejectUnacceptedDictationRequest(reason: .modelLoadFailed)
      return
    }
    self.startCapture()
  }

  private func rejectUnacceptedDictationRequest(
    reason: FeatureDiagnostics.FailureReason? = nil,
    outcome: DictationOutcome? = .activationFailed
  ) {
    self.settings.synchronize()
    guard DictationCapturePolicy.canRejectUnacceptedRequest(
      activeToken: self.activeDictationToken, recording: self.isRecording,
      finalizing: self.isStopping, ownsCapture: self.session.captureOwner == .dictation
    ), !self.settings.dictationCancellationRequested,
      let token = self.settings.dictationSessionToken else { return }
    self.settings.isRecording = false
    self.settings.recordingStartedAt = 0
    self.settings.keyboardRequestedDictation = false
    self.settings.lastDictationOutcome = outcome
    self.settings.dictationSessionToken = nil
    self.settings.synchronize()
    MicrophoneHoldStopIntent.clear(defaults: self.settings.defaults)
    if TranscriptionBridge.readVoiceProgress()?.sessionToken == token {
      TranscriptionBridge.clearVoiceProgress()
    }
    FeatureDiagnostics.record(.speech, .rejected,
      failureReason: reason, operationID: token, phase: .rejected)
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStopped)
  }

  func startCapture() {
    self.settings.synchronize()
    guard !self.settings.dictationCancellationRequested,
          self.settings.dictationSessionToken == nil
            || self.settings.dictationSessionToken != TranscriptionBridge.cancellationToken()
    else { return }
    let micAuth = self.settings.isMicrophoneAuthorized

    guard !LocalUserDataStore.isExporting,
          !self.isRecording, !self.isStopping,
          !MeetingRecordingCoordinator.shared.isRecording,
          !MeetingRecordingCoordinator.shared.isFinalizing,
          ConversationCoordinator.shared.recordingSide == nil,
          !ConversationCoordinator.shared.processing,
          MeetingRecordingCoordinator.shared.translatingRecordID == nil else {
      self.rejectUnacceptedDictationRequest(reason: .busy)
      return
    }
    guard micAuth else {
      FeatureDiagnostics.record(.speech, .blocked)
      self.errorMessage = "Microphone access is required for voice input."
      self.rejectUnacceptedDictationRequest(reason: .audioCaptureUnavailable)
      return
    }

    self.errorMessage = nil
    self.currentTranscription = ""
    self.currentRawTranscription = ""
    self.currentWordBoundaries = nil
    self.recordingSpokenLanguages = self.settings.preferredSpokenLanguages
    self.settings.lastVoiceOutputProcessed = false
    self.settings.lastDictationOutcome = nil
    if self.settings.dictationSessionToken == nil {
      self.settings.dictationSessionToken = UUID().uuidString
    }
    self.activeDictationToken = self.settings.dictationSessionToken
    self.settings.isRecording = false
    self.settings.recordingStartedAt = 0
    TranscriptionBridge.clearTranscription()
    TranscriptionBridge.clearVoiceProgress()
    ExperimentalLiveTranscription.clear()
    self.currentAudioFileName = "\(UUID().uuidString).caf"

    let sessionStartedHere = !self.session.isSessionHealthy
    FeatureDiagnostics.record(.speechAudio,
      sessionStartedHere ? .fallback : .selected,
      failureReason: sessionStartedHere ? .coldAudioSessionStart : nil,
      operationID: self.activeDictationToken)
    guard self.ensureSessionActive() else {
      FeatureDiagnostics.record(.speech, .failed, failureReason: .audioCaptureUnavailable,
        operationID: self.activeDictationToken, phase: .failed)
      self.currentAudioFileName = nil
      self.settings.dictationSessionToken = nil
      self.activeDictationToken = nil
      self.settings.lastDictationOutcome = .activationFailed
      self.settings.synchronize()
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStopped)
      return
    }

    self.accumulator.reset()
    do {
      try self.startAudioCapture()
    } catch {
      FeatureDiagnostics.record(.speech, .failed, failureReason: .audioCaptureUnavailable,
        operationID: self.activeDictationToken, phase: .failed)
      self.errorMessage = error.localizedDescription
      self.settings.lastDictationOutcome = .activationFailed
      if let recording = self.audioRecorder.stopRecording() {
        try? FileManager.default.removeItem(at: recording.url)
      }
      self.currentAudioFileName = nil
      self.settings.dictationSessionToken = nil
      self.activeDictationToken = nil
      self.accumulator.reset()
      self.session.endCapture(owner: .dictation)
      if sessionStartedHere { self.session.endSession() }
      self.settings.synchronize()
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStopped)
      return
    }

    self.isRecording = true
    self.settings.recordingStartedAt = Date().timeIntervalSinceReferenceDate
    self.settings.synchronize()
    self.armMaxDurationTimer()
    self.awaitCaptureConfirmation()
  }

  private func awaitCaptureConfirmation() {
    self.captureConfirmationTask?.cancel()
    guard let token = self.activeDictationToken else { return }
    let startedAt = CFAbsoluteTimeGetCurrent()
    FeatureDiagnostics.record(.speechAudio, .queued,
      operationID: token, phase: .accepted)
    self.captureConfirmationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer {
        if self.activeDictationToken == token { self.captureConfirmationTask = nil }
      }
      while !Task.isCancelled {
        guard self.isRecording, !self.isStopping,
              self.activeDictationToken == token else { return }
        self.settings.synchronize()
        if self.settings.dictationCancellationRequested
            || TranscriptionBridge.cancellationToken() == token {
          self.cancelRecording()
          return
        }
        guard DictationRequestPolicy.isCurrent(
          started: token, current: self.settings.dictationSessionToken,
          cancelled: self.settings.dictationCancellationRequested
        ) else {
          self.failUnconfirmedCapture(token: token, reason: .audioCaptureUnavailable)
          return
        }
        // A status request can confirm the same capture before this poll.
        if self.settings.isRecording { return }
        switch self.session.captureConfirmation(
          owner: .dictation, elapsed: CFAbsoluteTimeGetCurrent() - startedAt
        ) {
        case .confirmed:
          self.acknowledgeCaptureIfReady()
          return
        case .unavailable:
          self.failUnconfirmedCapture(token: token, reason: .audioCaptureUnavailable)
          return
        case .timedOut:
          self.failUnconfirmedCapture(token: token, reason: .audioCaptureUnconfirmed)
          return
        case .waiting:
          do { try await Task.sleep(for: .milliseconds(50)) }
          catch { return }
        }
      }
    }
  }

  private func acknowledgeCaptureIfReady() {
    self.settings.synchronize()
    guard self.isRecording, !self.isStopping,
          let token = self.activeDictationToken,
          DictationRequestPolicy.isCurrent(
            started: token, current: self.settings.dictationSessionToken,
            cancelled: self.settings.dictationCancellationRequested
          ), token != TranscriptionBridge.cancellationToken(),
          self.session.captureConfirmation(owner: .dictation) == .confirmed else { return }
    let firstAcknowledgment = !self.settings.isRecording
    self.settings.isRecording = true
    self.settings.synchronize()
    if firstAcknowledgment {
      LiveDictationLatency.mark(.audioCaptured, token: token)
      FeatureDiagnostics.record(.speech, .started,
        operationID: token, phase: .running)
    }
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStarted)
    if firstAcknowledgment, self.speechWorkers == 0,
       self.llmCoordinator?.isProcessing != true {
      self.scheduleQwenWarmupAfterCapture(token: token)
      self.startExperimentalLiveIfNeeded()
    }
    // A hold may end before the keyboard receives the recording-start
    // notification. Honor that release exactly once after capture exists.
    if MicrophoneHoldStopIntent.consume(
      for: self.settings.dictationSessionToken, defaults: self.settings.defaults
    ) {
      Task { @MainActor [weak self] in
        guard let self, self.isRecording, self.activeDictationToken == token else { return }
        await self.stopRecording()
      }
    }
  }

  private func failUnconfirmedCapture(
    token: String, reason: FeatureDiagnostics.FailureReason
  ) {
    guard self.activeDictationToken == token, self.isRecording, !self.isStopping else { return }
    self.captureConfirmationTask?.cancel()
    self.captureConfirmationTask = nil
    self.cancelMaxDurationTimer()
    self.isRecording = false
    let canEndSession = self.session.captureOwner == nil || self.session.captureOwner == .dictation
    self.session.endCapture(owner: .dictation)
    self.saveHistoryRecord(preserveUntranscribedAudio: true)
    self.accumulator.reset()
    self.activeDictationToken = nil
    self.settings.synchronize()
    if self.settings.dictationSessionToken == token {
      self.settings.isRecording = false
      self.settings.recordingStartedAt = 0
      self.settings.lastDictationOutcome = .activationFailed
      self.settings.dictationSessionToken = nil
      self.settings.keyboardRequestedDictation = false
      self.settings.synchronize()
      MicrophoneHoldStopIntent.clear(defaults: self.settings.defaults)
      TranscriptionBridge.clearVoiceProgress()
    }
    if canEndSession { self.session.endSession() }
    FeatureDiagnostics.record(.speechAudio, .failed,
      failureReason: reason, operationID: token, phase: .failed)
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStopped)
  }

  /// Warm the offline recognizer while the user speaks, not before audio
  /// capture. The first audio buffers and host-return action take priority.
  /// If the process lacks RAM, finalization still loads Qwen3 after stop.
  private func scheduleQwenWarmupAfterCapture(token: String) {
    guard self.settings.selectedVariant.engine == .qwen3,
          self.activeLoadState == .unloaded else { return }

    Task { @MainActor [weak self] in
      // Give the microphone and host-return task the first scheduling turn.
      do { try await Task.sleep(for: .milliseconds(200)) }
      catch { return }

      guard let self, self.isRecording, self.activeDictationToken == token,
            self.settings.selectedVariant.engine == .qwen3,
            self.activeLoadState == .unloaded,
            let downloads = self.downloadService
      else { return }

      // Release unused recognizers first, not the currently recording tap.
      // This reduces live-model peak memory without hiding an OOM.
      await self.releaseInactiveSpeechEnginesForQwen()
      guard self.isRecording, self.activeDictationToken == token,
            self.settings.selectedVariant.engine == .qwen3,
            self.activeLoadState == .unloaded else { return }
      let variant = self.settings.selectedVariant
      let availableMB = Int(os_proc_available_memory() / 1_048_576)
      let wantsLive = self.settings.experimentalLiveDictationEnabled
      let minimumMB = LiveWarmupMemoryPolicy.requiredAvailableMB(
        requirementMB: variant.ramRequirementMB, wantsLive: wantsLive
      )
      guard LiveWarmupMemoryPolicy.allowsWarmup(
        availableMB: availableMB, requirementMB: variant.ramRequirementMB,
        wantsLive: wantsLive
      ) else {
        if wantsLive {
          self.liveDictationStatus = "Insufficient memory to warm Qwen while recording"
          FeatureDiagnostics.record(.liveDictation, .fallback,
            failureReason: .insufficientMemory)
        }
        DictationBreadcrumb.record(
          "qwen: deferred warmup (available \(availableMB)MB, budget \(minimumMB)MB)"
        )
        return
      }

      DictationBreadcrumb.record(
        "qwen: warming during active recording (available \(availableMB)MB)"
      )
      self.settings.isModelLoading = true
      if wantsLive { self.liveDictationStatus = "Loading Qwen3-ASR" }
      defer { self.settings.isModelLoading = false }
      await self.loadModelIfAvailable(downloadService: downloads)
      guard self.activeDictationToken == token else { return }
      if wantsLive {
        self.liveDictationStatus = self.activeLoadState == .loaded
          ? "Recognizer ready" : "Recognizer could not load"
        if self.activeLoadState != .loaded {
          FeatureDiagnostics.record(.liveDictation, .fallback,
            failureReason: .modelLoadFailed)
        }
      }
      DictationBreadcrumb.record(
        "qwen: concurrent warmup ended in state \(String(describing: self.activeLoadState))"
      )
    }
  }

  private func releaseInactiveSpeechEnginesForQwen() async {
    guard self.isRecording, self.speechWorkers == 0,
          self.modelLoadsInFlight == 0,
          self.settings.selectedVariant.engine == .qwen3 else { return }
    if self.whisperService.loadState == .loaded { await self.whisperService.unloadModel() }
    if self.parakeetService.loadState == .loaded { await self.parakeetService.unloadModel() }
    if self.moonshineService.loadState == .loaded { self.moonshineService.unloadModel() }
    if self.senseVoiceService.loadState == .loaded { self.senseVoiceService.unloadModel() }
    if self.settings.selectedVariant == .qwen3ASR17BCantoneseHK {
      if self.qwen3Service.loadState == .loaded { self.qwen3Service.unloadModel() }
    } else if self.qwenHKService.loadState == .loaded {
      self.qwenHKService.unloadModel()
    }
  }

  func stopRecording() async {

    guard !self.isStopping else {
      return
    }
    guard self.isRecording else {
      // Hold release can race an asynchronous start request. Keep its stop
      // intent until the first audio-capture acknowledgment.
      if MicrophoneHoldStopIntent.isRequested(
        for: self.settings.dictationSessionToken, defaults: self.settings.defaults
      ) { return }
      self.settings.isRecording = false
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStopped)
      return
    }
    self.isRecording = false
    self.captureConfirmationTask?.cancel()
    self.captureConfirmationTask = nil
    FeatureDiagnostics.record(.speech, .stopped,
      operationID: self.activeDictationToken, phase: .accepted)
    self.settings.isRecording = false
    self.settings.recordingStartedAt = 0
    self.isStopping = true
    let finalizationToken = self.activeDictationToken
    MicrophoneHoldStopIntent.clear(defaults: self.settings.defaults)
    self.settings.synchronize()
    TranscriptionBridge.writeVoiceProgress(.stoppingAudio)
    self.cancelMaxDurationTimer()
    self.session.endCapture(owner: .dictation)
    let task = Task { @MainActor in
      await self.finishRecording(token: finalizationToken)
    }
    self.finalizationTask = task
    await task.value
  }

  private func finishRecording(token finalizationToken: String?) async {
    defer {
      if self.activeDictationToken == finalizationToken {
        self.isStopping = false
        self.activeDictationToken = nil
        self.finalizationTask = nil
      }
    }
    guard self.isCurrentDictation(finalizationToken) else { return }
    let finalizationStartedAt = CFAbsoluteTimeGetCurrent()
    let liveStopped = await self.stopExperimentalLive()
    guard self.isCurrentDictation(finalizationToken) else { return }
    if !liveStopped && self.speechWorkers > 0 {
      // Starting a second Qwen decode while the native worker is still
      // running would race a shared recognizer and can exhaust iPhone RAM.
      // Save the recording, even without recognized words, before resetting.
      self.settings.lastDictationOutcome = .processingFailed
      self.currentRawTranscription = ExperimentalLiveTranscription.read()?.text ?? ""
      self.currentTranscription = self.currentRawTranscription
      self.saveHistoryRecord(preserveUntranscribedAudio: true)
      self.accumulator.reset()
      self.settings.isRecording = false
      self.settings.dictationSessionToken = nil
      self.settings.synchronize()
      TranscriptionBridge.clearVoiceProgress()
      FeatureDiagnostics.record(.speechFinalization, .failed,
        durationMs: Int((CFAbsoluteTimeGetCurrent() - finalizationStartedAt) * 1_000))
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStopped)
      return
    }
    // Only the final recognizer needs these samples now; release the queued copy.
    let savedSamples = self.accumulator.consumeAll()
    let stylingHost = OnboardingTextEntry.stylingHost(self.settings.hostBundleId)

    // Keep the armed tap alive during ASR. iOS can reject reactivation after
    // leaving the foreground. endCapture already stopped writing audio.
    let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "VoiceFinalization") {
      DictationBreadcrumb.record("voice: background finalization time expired")
    }
    defer {
      if backgroundTask != .invalid {
        UIApplication.shared.endBackgroundTask(backgroundTask)
      }
    }

    // A cancelled native decoder may still be unwinding. Capture can restart
    // independently, but two inferences must never use a model concurrently.
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(15))
    while (self.speechWorkers > 0 || self.llmCoordinator?.isProcessing == true),
          clock.now < deadline {
      do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
      guard self.isCurrentDictation(finalizationToken) else { return }
    }

    if self.speechWorkers > 0 || self.llmCoordinator?.isProcessing == true {
      self.settings.lastDictationOutcome = .processingFailed
      FeatureDiagnostics.record(.speech, .failed, failureReason: .busy,
        operationID: finalizationToken, phase: .failed)
    } else {
      if self.activeLoadState != .loaded {
        TranscriptionBridge.writeVoiceProgress(.loadingRecognizer)
        if self.activeLoadState == .loading {
          await self.awaitModelLoad()
        } else if let downloadService {
          downloadService.verifyExistingModels()
          await self.loadModelIfAvailable(downloadService: downloadService)
        }
      }
      guard self.isCurrentDictation(finalizationToken) else { return }
      TranscriptionBridge.writeVoiceProgress(.transcribing)
      await self.runFinalTranscription(samples: savedSamples, stylingHost: stylingHost)
      guard self.isCurrentDictation(finalizationToken) else { return }
    }
    if self.settings.lastDictationOutcome == nil,
       !TranscriptionBridge.writeTranscription(self.currentTranscription, token: finalizationToken) {
      self.settings.lastDictationOutcome = .processingFailed
    }
    let finalizationEvent: FeatureDiagnostics.Event
    switch self.settings.lastDictationOutcome {
    case nil: finalizationEvent = .completed
    case .some(.noSpeech): finalizationEvent = .noSpeech
    default: finalizationEvent = .failed
    }
    FeatureDiagnostics.record(.speechFinalization, finalizationEvent,
      durationMs: Int((CFAbsoluteTimeGetCurrent() - finalizationStartedAt) * 1_000),
      operationID: finalizationToken)

    // A recognizer or post-processing failure must not discard valid audio.
    // An explicit no-speech result retains the prior silence-handling policy.
    let retainUndecodedAudio = self.settings.lastDictationOutcome == .engineFailed
      || self.settings.lastDictationOutcome == .processingFailed
    self.saveHistoryRecord(preserveUntranscribedAudio: retainUndecodedAudio)
    if finalizationEvent == .completed {
      self.settings.chargeFreeWords(WordCounter.count(self.currentTranscription))
    }

    self.isStopping = false
    self.settings.isRecording = false
    self.settings.dictationSessionToken = nil
    self.settings.synchronize()
    TranscriptionBridge.clearVoiceProgress()
    if finalizationEvent == .completed {
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.transcriptionReady)
    }
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStopped)
  }

  func cancelRecording() {
    guard let token = self.activeDictationToken,
          self.isRecording || self.isStopping else { return }
    FeatureDiagnostics.record(.speech, .cancelled, operationID: token, phase: .cancelled)
    self.finalizationTask?.cancel()
    self.finalizationTask = nil
    self.captureConfirmationTask?.cancel()
    self.captureConfirmationTask = nil
    self.experimentalLiveTask?.cancel()
    self.experimentalLiveTask = nil
    ExperimentalLiveTranscription.clear()
    self.cancelMaxDurationTimer()
    self.session.endCapture(owner: .dictation)
    if let recording = self.audioRecorder.stopRecording() {
      try? FileManager.default.removeItem(at: recording.url)
    }
    self.accumulator.reset()
    self.activeDictationToken = nil
    self.isRecording = false
    self.isStopping = false
    self.liveDictationStatus = "Cancelled"
    self.currentTranscription = ""
    self.currentRawTranscription = ""
    self.currentAudioFileName = nil

    self.settings.synchronize()
    if self.settings.dictationSessionToken == token {
      MicrophoneHoldStopIntent.clear(defaults: self.settings.defaults)
      self.settings.isRecording = false
      self.settings.recordingStartedAt = 0
      self.settings.keyboardRequestedDictation = false
      self.settings.dictationCancellationRequested = true
      self.settings.dictationSessionToken = nil
      self.settings.synchronize()
    }
    if TranscriptionBridge.readVoiceProgress()?.sessionToken == token {
      TranscriptionBridge.clearVoiceProgress()
    }
    if let delivery = TranscriptionBridge.readDelivery(
      matching: token, allowAnyDestination: true, includeUncommitted: true
    ) {
      TranscriptionBridge.acknowledgeDelivery(delivery.resultID)
    }
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStopped)
  }

  /// One ASR dispatch for keyboard dictation, Meetings and future Conversation.
  /// All consumers reuse the existing microphone session and model owners.
  func transcribeSamples(_ samples: [Float]) async -> TranscriptionResult {
    guard self.llmCoordinator?.isProcessing != true, self.speechWorkers == 0 else {
      FeatureDiagnostics.record(.speechDecode, .blocked, failureReason: .busy)
      return .failed("Speech model is busy")
    }
    self.speechWorkers += 1
    defer { self.speechWorkers -= 1 }
    switch self.settings.selectedVariant.engine {
    case .whisperKit:
      return await self.whisperService.transcribe(audioSamples: samples)
    case .parakeet:
      return await self.parakeetService.transcribe(audioSamples: samples)
    case .moonshine:
      return await self.moonshineService.transcribe(audioSamples: samples)
    case .qwen3:
      if self.settings.selectedVariant == .qwen3ASR17BCantoneseHK {
        return await self.qwenHKService.transcribe(audioSamples: samples)
      }
      return await self.qwen3Service.transcribe(audioSamples: samples)
    case .senseVoice:
      return await self.senseVoiceService.transcribe(audioSamples: samples)
    }
  }

  func loadModelIfAvailable(downloadService: ModelDownloadService) async {
    let selected = self.settings.selectedVariant
    guard let url = downloadService.activeModelFolderURL else { return }
    _ = await self.loadModel(variant: selected, from: url)
  }

  func reloadModel(variant: ModelVariant, folderURL: URL?) async {
    // Temporarily park the engine before allocating a cold recognizer.
    let parkedAudio = variant.engine == .qwen3 && !self.isRecording
      && self.session.suspendForModelLoad()
    defer {
      if parkedAudio {
        self.restoreParkedAudioSession(allowed: !self.isRecording)
      }
    }
    await self.unloadAllEngines()
    guard let folderURL else { return }
    _ = await self.loadModel(variant: variant, from: folderURL)
  }

  private func restoreParkedAudioSession(
    allowed: Bool, operationID: String? = nil
  ) {
    guard let restored = self.session.restoreAfterModelLoad(allowed: allowed)
    else { return }
    FeatureDiagnostics.record(.speechAudio, restored ? .resumed : .failed,
      failureReason: restored ? nil : .audioSessionRestoreFailed,
      operationID: operationID)
  }

  func unloadForLLMProcessing() async -> Bool {
    guard self.canBeginTextWork else { return false }
    await self.unloadAllEngines()
    return true
  }

  func deactivateCompletely() async {
    // Revoke parked recovery before suspension in the model unload.
    // Otherwise the finalizer could briefly reactivate a manually stopped mic.
    self.session.endSession()
    await self.unloadAllEngines()
  }

  func startRecordingAfterModelLoad() async {
    self.settings.synchronize()
    guard !self.settings.dictationCancellationRequested,
          !self.isRecording, !self.isStopping else { return }
    if self.settings.selectedVariant.engine == .qwen3 {
      // Qwen3 loads after capture ends to avoid delaying microphone startup.
      self.startCapture()
      if self.isRecording {
        DictationBreadcrumb.record("qwen: recording started, cold recognizer deferred until stop")
      }
      return
    }
    if self.activeLoadState == .loaded {
      self.startRecording()
    } else {
      self.startCapture()
      guard self.isRecording, self.speechWorkers == 0,
            self.llmCoordinator?.isProcessing != true, let downloadService else { return }
      self.settings.isModelLoading = true
      Task {
        defer { self.settings.isModelLoading = false }
        downloadService.verifyExistingModels()
        await self.loadModelIfAvailable(downloadService: downloadService)
      }
    }
  }

  private var errorMessage: String?
  private var sessionCancellable: AnyCancellable?

  private var requestStartObserver: DarwinNotificationObserver?
  private var requestStopObserver: DarwinNotificationObserver?
  private var requestCancelObserver: DarwinNotificationObserver?
  private var sessionStatusObserver: DarwinNotificationObserver?
  private var keyboardVoiceActivityObserver: DarwinNotificationObserver?

  private var maxDurationTimer: Timer?

  private func armMaxDurationTimer() {
    self.maxDurationTimer?.invalidate()
    let cap = Self.maxRecordingDuration
    self.maxDurationTimer = Timer.scheduledTimer(
      withTimeInterval: cap,
      repeats: false,
    ) { [weak self] _ in
      Task { @MainActor [weak self] in await self?.stopRecording() }
    }
  }

  private func cancelMaxDurationTimer() {
    self.maxDurationTimer?.invalidate()
    self.maxDurationTimer = nil
  }

  private func awaitModelLoad() async {
    switch self.settings.selectedVariant.engine {
    case .whisperKit:
      await self.whisperService.waitForLoad()
    case .parakeet:
      await self.parakeetService.waitForLoad()
    case .moonshine:
      await self.moonshineService.waitForLoad()
    case .qwen3:
      if self.settings.selectedVariant == .qwen3ASR17BCantoneseHK {
        await self.qwenHKService.waitForLoad()
      } else {
        await self.qwen3Service.waitForLoad()
      }
    case .senseVoice:
      await self.senseVoiceService.waitForLoad()
    }
  }

  private func parakeetModelVersion(for variant: ModelVariant) -> AsrModelVersion {
    switch variant {
    case .parakeetV2: .v2
    case .parakeetV3: .v3
    default: .v3
    }
  }

  private func unloadAllEngines() async {
    await self.whisperService.unloadModel()
    await self.parakeetService.unloadModel()
    self.moonshineService.unloadModel()
    self.qwen3Service.unloadModel()
    self.qwenHKService.unloadModel()
    self.senseVoiceService.unloadModel()
  }

  private func ensureSessionActive() -> Bool {
    guard !self.session.isSessionHealthy else {
      return true
    }
    do {
      try self.session.startSession()
      return self.session.isSessionHealthy
    } catch {
      self.errorMessage = String(
        localized: "Failed to configure audio session.",
        comment: "Error when audio session setup fails",
      )
      return false
    }
  }

  private func startAudioCapture() throws {
    let inputNode = self.session.audioEngine.inputNode
    let recordingFormat = inputNode.outputFormat(forBus: 0)

    if let fileName = currentAudioFileName,
       self.audioRecorder.startRecording(fileName: fileName, format: recordingFormat) == nil {
      // Dictation still works without a history file; report the fallback.
      self.currentAudioFileName = nil
      FeatureDiagnostics.record(.speech, .fallback)
    }

    try self.session.beginCapture(owner: .dictation, accumulator: self.accumulator, recorder: self.audioRecorder)
    if self.settings.selectedVariant.engine == .parakeet,
       self.speechWorkers == 0, self.llmCoordinator?.isProcessing != true {
      self.parakeetService.warmUpIfEvicted()
    }
  }

}

extension SpeechRecognitionService {

  func setupDarwinObservers() {
    self.setupDictationObservers()
    self.keyboardVoiceActivityObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.keyboardVoiceActivityChanged
    ) { [weak self] in
      Task { @MainActor [weak self] in self?.session.keyboardActivityDidChange() }
    }
    self.sessionStatusObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.requestSessionStatus
    ) { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        // Do not acknowledge an armed microphone from a stale shared flag.
        let healthy = self.session.isSessionHealthy
        if healthy {
          TranscriptionBridge.postDarwinNotification(DarwinNotificationName.sessionStarted)
        }
        if self.isStopping {
          TranscriptionBridge.postDarwinNotification(DarwinNotificationName.voiceProgressUpdated)
        } else if self.isRecording {
          self.acknowledgeCaptureIfReady()
        }
      }
    }
  }

  func setupSessionCallbacks() {
    self.session.onInterruptionBegan = { [weak self] in
      Task { @MainActor [weak self] in
        if MeetingRecordingCoordinator.shared.isRecording {
          MeetingRecordingCoordinator.shared.stop(interrupted: true)
        } else if ConversationCoordinator.shared.recordingSide != nil, let self {
          await ConversationCoordinator.shared.stop(using: self)
        } else {
          await self?.stopRecording()
        }
      }
    }
    self.session.onSessionEnded = { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if ConversationCoordinator.shared.recordingSide != nil {
          await ConversationCoordinator.shared.stop(using: self)
        } else if self.isRecording {
          await self.stopRecording()
        }
      }
    }
  }

  func forwardSessionState() {
    self.sessionCancellable = self.session.$isSessionActive
      .receive(on: DispatchQueue.main)
      .sink { [weak self] active in
        self?.isSessionActive = active
      }
  }

  private func hasValidSessionToken(caller _: String) -> Bool {
    let tokenSettings = SharedSettings()
    tokenSettings.synchronize()
    guard tokenSettings.dictationSessionToken != nil else {
      return false
    }
    return true
  }

  private func setupDictationObservers() {
    self.requestStartObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.requestStartDictation
    ) { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else {
          return
        }
        guard self.hasValidSessionToken(caller: "requestStartDictation") else { return }
        self.settings.synchronize()
        if let active = self.activeDictationToken,
           active != self.settings.dictationSessionToken
             || active == TranscriptionBridge.cancellationToken() {
          self.cancelRecording()
        }
        guard !self.settings.dictationCancellationRequested else { return }
        // An unarmed background app cannot activate the microphone. Keep this
        // request intact so the keyboard can offer its foreground recovery.
        guard self.session.isSessionHealthy
                || UIApplication.shared.applicationState != .background else {
          FeatureDiagnostics.record(.speechAudio, .fallback,
            failureReason: .coldAudioSessionStart,
            operationID: self.settings.dictationSessionToken, phase: .accepted)
          return
        }
        guard !self.settings.isDictationLocked else {
          self.rejectUnacceptedDictationRequest(outcome: nil)
          TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationLockChanged)
          return
        }
        if self.isRecording {
          // Replayed Darwin starts are acknowledgements, not new captures.
          guard self.activeDictationToken == self.settings.dictationSessionToken else {
            FeatureDiagnostics.record(.speech, .rejected)
            return
          }
          self.acknowledgeCaptureIfReady()
          return
        }
        await self.startRecordingAfterModelLoad()
      }
    }

    self.requestCancelObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.requestCancelDictation
    ) { [weak self] in
      Task { @MainActor [weak self] in
        guard let self, OperationPolicy.ownsCancellation(
          requested: TranscriptionBridge.cancellationToken(), active: self.activeDictationToken
        ) else { return }
        self.cancelRecording()
      }
    }

    self.requestStopObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.requestStopDictation
    ) { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else {
          return
        }
        guard OperationPolicy.ownsCancellation(
          requested: TranscriptionBridge.stopToken(), active: self.activeDictationToken
        ) else { return }
        if DictationCapturePolicy.shouldDeferRequestedStop(
          confirmation: self.session.captureConfirmation(owner: .dictation),
          awaitingConfirmation: self.isRecording && !self.isStopping
            && self.captureConfirmationTask != nil
        ) {
          MicrophoneHoldStopIntent.request(
            for: self.activeDictationToken, defaults: self.settings.defaults
          )
          FeatureDiagnostics.record(.speech, .queued,
            operationID: self.activeDictationToken, phase: .accepted)
          return
        }
        await self.stopRecording()
      }
    }
  }

}

extension SpeechRecognitionService: ModelLoading {

  func loadModel(variant: ModelVariant, from url: URL) async -> Bool {
    guard self.llmCoordinator?.isProcessing != true else { return false }
    self.modelLoadsInFlight += 1
    defer { self.modelLoadsInFlight -= 1 }
    switch variant.engine {
    case .whisperKit:
      await self.whisperService.loadModel(variant: variant, from: url.path)
      return self.whisperService.loadState == .loaded

    case .parakeet:
      let version = self.parakeetModelVersion(for: variant)
      await self.parakeetService.loadModel(from: url, version: version)
      if self.isRecording {
        self.parakeetService.warmUpIfEvicted()
      }
      return self.parakeetService.loadState == .loaded

    case .qwen3:
      if variant == .qwen3ASR17BCantoneseHK {
        await self.qwenHKService.loadModel(from: url)
        return self.qwenHKService.loadState == .loaded
      }
      await self.qwen3Service.loadModel(from: url)
      return self.qwen3Service.loadState == .loaded
    case .senseVoice:
      await self.senseVoiceService.loadModel(from: url)
      return self.senseVoiceService.loadState == .loaded
    case .moonshine:
      guard let arch = variant.moonshineModelArch else { return false }
      await self.moonshineService.loadModel(from: url.path, archName: arch)
      return self.moonshineService.loadState == .loaded
    }
  }
}


