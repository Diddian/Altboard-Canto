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
  let senseVoiceService = SenseVoiceTranscriptionService()
  weak var downloadService: ModelDownloadService?
  weak var llmCoordinator: LLMProcessingCoordinator?

  let settings = SharedSettings()
  let accumulator = AudioBufferAccumulator()
  let audioRecorder = AudioRecorder()
  private(set) var activeDictationToken: String?
  private(set) var speechWorkers = 0
  private var modelLoadsInFlight = 0
  private var cancellationTask: Task<Void, Never>?

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
    case .qwen3: self.qwen3Service.loadState
    case .senseVoice: self.senseVoiceService.loadState
    }
  }

  func startRecording() {
    guard self.activeLoadState == .loaded else { return }
    self.settings.dictationCancellationRequested = false
    self.startCapture()
  }

  func startCapture() {
    self.settings.synchronize()
    guard !self.settings.dictationCancellationRequested else { return }
    let micAuth = self.settings.isMicrophoneAuthorized

    guard !LocalUserDataStore.isExporting,
          !self.isRecording, !self.isStopping,
          !MeetingRecordingCoordinator.shared.isRecording,
          !MeetingRecordingCoordinator.shared.isFinalizing,
          ConversationCoordinator.shared.recordingSide == nil,
          !ConversationCoordinator.shared.processing,
          MeetingRecordingCoordinator.shared.translatingRecordID == nil,
          self.llmCoordinator?.isProcessing != true, self.speechWorkers == 0 else {
      return
    }
    guard micAuth else {
      FeatureDiagnostics.record(.speech, .blocked)
      self.errorMessage = "Microphone access is required for voice input."
      return
    }

    self.errorMessage = nil
    self.currentTranscription = ""
    self.currentRawTranscription = ""
    self.recordingSpokenLanguages = self.settings.preferredSpokenLanguages
    self.settings.lastVoiceOutputProcessed = false
    self.settings.lastDictationOutcome = nil
    if self.settings.dictationSessionToken == nil {
      self.settings.dictationSessionToken = UUID().uuidString
    }
    self.activeDictationToken = self.settings.dictationSessionToken
    TranscriptionBridge.clearTranscription()
    TranscriptionBridge.clearVoiceProgress()
    ExperimentalLiveTranscription.clear()
    self.currentAudioFileName = "\(UUID().uuidString).caf"

    let sessionStartedHere = !self.session.isSessionActive
    guard self.ensureSessionActive() else {
      FeatureDiagnostics.record(.speech, .failed)
      self.currentAudioFileName = nil
      self.settings.dictationSessionToken = nil
      self.settings.lastDictationOutcome = .activationFailed
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStopped)
      return
    }

    self.accumulator.reset()
    do {
      try self.startAudioCapture()
    } catch {
      FeatureDiagnostics.record(.speech, .failed)
      self.errorMessage = error.localizedDescription
      self.settings.lastDictationOutcome = .activationFailed
      if let recording = self.audioRecorder.stopRecording() {
        try? FileManager.default.removeItem(at: recording.url)
      }
      self.currentAudioFileName = nil
      self.settings.dictationSessionToken = nil
      self.accumulator.reset()
      self.session.endCapture(owner: .dictation)
      if sessionStartedHere { self.session.endSession() }
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStopped)
      return
    }

    self.isRecording = true
    if let token = self.activeDictationToken {
      LiveDictationLatency.mark(.audioCaptured, token: token)
    }
    FeatureDiagnostics.record(.speech, .started,
      operationID: self.activeDictationToken, phase: .running)
    self.settings.isRecording = true
    self.settings.recordingStartedAt = Date().timeIntervalSinceReferenceDate
    self.armMaxDurationTimer()
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStarted)
    self.scheduleQwenWarmupAfterCapture()
    self.startExperimentalLiveIfNeeded()
    // A hold may end before the keyboard receives the recording-start
    // notification. Honor that release exactly once after capture exists.
    if MicrophoneHoldStopIntent.consume(
      for: self.settings.dictationSessionToken, defaults: self.settings.defaults
    ) {
      Task { @MainActor [weak self] in
        guard let self, self.isRecording else { return }
        await self.stopRecording()
      }
    }
  }

  /// Warm the offline recognizer while the user speaks, not before audio
  /// capture. The first audio buffers and host-return action take priority.
  /// If the process lacks RAM, finalization still loads Qwen3 after stop.
  private func scheduleQwenWarmupAfterCapture() {
    guard self.settings.selectedVariant.engine == .qwen3,
          self.activeLoadState == .unloaded else { return }

    Task { @MainActor [weak self] in
      // Give the microphone and host-return task the first scheduling turn.
      do { try await Task.sleep(for: .milliseconds(200)) }
      catch { return }

      guard let self, self.isRecording, !self.isStopping,
            self.settings.selectedVariant.engine == .qwen3,
            self.activeLoadState == .unloaded,
            let downloads = self.downloadService
      else { return }

      // This model's published RAM requirement is an estimate. Keep an extra
      // 512 MB available for the recording engine and the OS.
      let variant = self.settings.selectedVariant
      let availableMB = Int(os_proc_available_memory() / 1_048_576)
      // Explicit live input permits a lower but still bounded warm-start
      // threshold. Otherwise the old conservative final-only path applies.
      let wantsLive = self.settings.experimentalLiveDictationEnabled
      let minimumMB = wantsLive
        ? max(2_400, Int(Double(variant.ramRequirementMB) * 0.58))
        : variant.ramRequirementMB + 512
      guard availableMB >= minimumMB else {
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
    FeatureDiagnostics.record(.speech, .stopped,
      operationID: self.activeDictationToken, phase: .accepted)
    self.settings.recordingStartedAt = 0
    self.isStopping = true
    let finalizationToken = self.activeDictationToken
    defer {
      if self.activeDictationToken == finalizationToken {
        self.isStopping = false
        self.activeDictationToken = nil
      }
    }
    let finalizationStartedAt = CFAbsoluteTimeGetCurrent()
    MicrophoneHoldStopIntent.clear(defaults: self.settings.defaults)
    TranscriptionBridge.writeVoiceProgress(.stoppingAudio)

    self.cancelMaxDurationTimer()
    self.session.endCapture(owner: .dictation)
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

    // Preserve the first words: capture before cold Qwen3 ONNX initialization.
    let coldQwen = self.settings.selectedVariant.engine == .qwen3 && self.activeLoadState != .loaded
    if coldQwen {
      self.settings.isModelLoading = true
      self.session.endSession()
    }
    defer { if coldQwen { self.settings.isModelLoading = false } }

    let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "VoiceFinalization") {
      DictationBreadcrumb.record("voice: background finalization time expired")
    }
    defer {
      if backgroundTask != .invalid {
        UIApplication.shared.endBackgroundTask(backgroundTask)
      }
    }

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
    let finalizationEvent: FeatureDiagnostics.Event
    switch self.settings.lastDictationOutcome {
    case nil: finalizationEvent = .completed
    case .some(.noSpeech): finalizationEvent = .noSpeech
    default: finalizationEvent = .failed
    }
    FeatureDiagnostics.record(.speechFinalization, finalizationEvent,
      durationMs: Int((CFAbsoluteTimeGetCurrent() - finalizationStartedAt) * 1_000))

    // A recognizer or post-processing failure must not discard valid audio.
    // An explicit no-speech result retains the prior silence-handling policy.
    let retainUndecodedAudio = self.settings.lastDictationOutcome == .engineFailed
      || self.settings.lastDictationOutcome == .processingFailed
    self.saveHistoryRecord(preserveUntranscribedAudio: retainUndecodedAudio)

    self.isStopping = false
    self.settings.isRecording = false
    self.settings.dictationSessionToken = nil
    self.settings.synchronize()
    TranscriptionBridge.clearVoiceProgress()
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStopped)
  }

  func cancelRecording() {
    guard self.cancellationTask == nil,
          (self.isRecording || self.isStopping),
          self.session.captureOwner == nil || self.session.captureOwner == .dictation,
          !MeetingRecordingCoordinator.shared.isRecording,
          !MeetingRecordingCoordinator.shared.isFinalizing,
          ConversationCoordinator.shared.recordingSide == nil else { return }
    FeatureDiagnostics.record(.speech, .cancelled,
      operationID: self.activeDictationToken, phase: .cancelled)
    MicrophoneHoldStopIntent.clear(defaults: self.settings.defaults)
    self.liveDictationStatus = "Cancelled"
    let cancelledLive = self.experimentalLiveTask
    cancelledLive?.cancel()
    self.experimentalLiveTask = nil
    ExperimentalLiveTranscription.clear()
    self.cancelMaxDurationTimer()
    self.session.endCapture(owner: .dictation)
    if let recording = self.audioRecorder.stopRecording() {
      try? FileManager.default.removeItem(at: recording.url)
    }
    self.session.endSession()
    self.accumulator.reset()
    self.isRecording = false
    self.isStopping = true
    let cancelledToken = self.activeDictationToken
    self.cancellationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.cancellationTask = nil }
      let nativeWorkerExited = await self.awaitExperimentalLiveWorkerExit(cancelledLive)
      guard self.activeDictationToken == cancelledToken else { return }
      if !nativeWorkerExited {
        // A stalled native decoder must not keep the cancellation owner alive.
        // speechWorkers still rejects new recording and inference until it exits.
        self.liveDictationStatus = "Native ASR still running; retry after it finishes"
        FeatureDiagnostics.record(.liveDictation, .slow, durationMs: 4_000)
      }
      self.activeDictationToken = nil
      self.isStopping = false
    }
    self.settings.isRecording = false
    self.settings.recordingStartedAt = 0
    self.settings.keyboardRequestedDictation = false
    self.settings.dictationCancellationRequested = true
    if let delivery = TranscriptionBridge.readDelivery(),
       delivery.sessionToken == cancelledToken {
      TranscriptionBridge.acknowledgeDelivery(delivery.resultID)
    }
    self.settings.dictationSessionToken = nil
    self.settings.synchronize()
    self.currentTranscription = ""
    self.currentRawTranscription = ""
    self.currentAudioFileName = nil
    TranscriptionBridge.clearTranscription()
    TranscriptionBridge.clearVoiceProgress()
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
    await self.unloadAllEngines()
    // Stop the persistent audio engine before initializing the larger Qwen3 ONNX model.
    if variant.engine == .qwen3, self.session.isSessionActive, !self.isRecording {
      self.session.endSession()
    }
    guard let folderURL else { return }
    _ = await self.loadModel(variant: variant, from: folderURL)
  }

  func unloadForLLMProcessing() async -> Bool {
    guard self.canBeginTextWork else { return false }
    await self.unloadAllEngines()
    return true
  }

  func deactivateCompletely() async {
    await self.unloadAllEngines()
    self.session.endSession()
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
      guard self.isRecording, let downloadService else { return }
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
      await self.qwen3Service.waitForLoad()
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
    self.senseVoiceService.unloadModel()
  }

  private func ensureSessionActive() -> Bool {
    guard !self.session.isSessionActive else {
      return true
    }
    do {
      try self.session.startSession()
      return true
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
    if self.settings.selectedVariant.engine == .parakeet {
      self.parakeetService.warmUpIfEvicted()
    }
  }

}

extension SpeechRecognitionService {

  func setupDarwinObservers() {
    self.setupDictationObservers()
    self.sessionStatusObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.requestSessionStatus
    ) { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        let active = self.session.isSessionActive
        let recording = self.isRecording
        if active {
          TranscriptionBridge.postDarwinNotification(DarwinNotificationName.sessionStarted)
        }
        if recording {
          TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationStarted)
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
        guard !self.settings.dictationCancellationRequested else { return }
        guard !self.settings.isDictationLocked else {
          TranscriptionBridge.postDarwinNotification(DarwinNotificationName.dictationLockChanged)
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


