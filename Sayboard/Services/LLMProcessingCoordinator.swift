
import Foundation

import UIKit

@MainActor
final class LLMProcessingCoordinator: ObservableObject {

  let inferenceService = LLMInferenceService()

  weak var speechService: SpeechRecognitionService?
  weak var downloadService: LLMDownloadService?

  @Published private(set) var isProcessing = false
  /// Human-readable, metadata-only error for the latest offline voice request.
  @Published private(set) var lastVoiceOutputIssue: String?

  func setupObservers() {
    self.requestObserver?.stopObserving()
    self.requestObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.requestLLMProcessing
    ) { [weak self] in
      Task { @MainActor [weak self] in
        await self?.handleProcessingRequest()
      }
    }
  }

  private struct ValidatedRequest {
    let request: LLMRequest
    let modelPath: String
    let variant: LLMModelVariant
  }

  private static let safetyMarginSeconds: TimeInterval = 5
  private static let inferenceTimeoutSeconds: TimeInterval = 120

  private var requestObserver: DarwinNotificationObserver?

  /// Optional cleanup or translation. Spoken dictation is never a Compose prompt.
  /// Long results are processed in small deterministic slices so the text model
  /// is not asked to fit an entire recording into a 1K/2K token context.
  func processVoiceDictation(_ input: String, options: VoiceOutputConfiguration) async -> String? {
    guard options.needsLLM, !input.isEmpty else { return nil }
    self.lastVoiceOutputIssue = nil
    let started = CFAbsoluteTimeGetCurrent()
    FeatureDiagnostics.record(.voiceOutput, .started)
    guard let backgroundTask = await self.beginVoiceProcessing() else { return nil }
    defer { self.endVoiceProcessing(backgroundTask) }

    let output = await self.processVoiceChunks(input, options: options)
    if output != nil {
      FeatureDiagnostics.record(
        .voiceOutput, .completed,
        durationMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1_000)
      )
    }
    return output
  }

  /// Both stages share one inference session, rather than repeatedly loading
  /// and unloading the same model between cleanup and translation.
  /// The callback publishes the cleaned original before translation completes.
  func processConversationTurn(
    _ source: String, options: VoiceOutputConfiguration,
    onCleaned: @escaping @MainActor (String) -> Void
  ) async -> String? {
    guard !source.isEmpty else { return nil }
    self.lastVoiceOutputIssue = nil
    let started = CFAbsoluteTimeGetCurrent()
    FeatureDiagnostics.record(.conversation, .started)
    guard let backgroundTask = await self.beginVoiceProcessing() else { return nil }
    defer { self.endVoiceProcessing(backgroundTask) }

    var cleaned: String?
    if options.cleanupEnabled {
      let cleanupOptions = VoiceOutputConfiguration(
        cleanupEnabled: true, target: .original,
        register: .faithful, customLanguage: ""
      )
      let cleanupStarted = CFAbsoluteTimeGetCurrent()
      cleaned = await self.processVoiceChunks(source, options: cleanupOptions)
      if let cleaned, !cleaned.isEmpty, !Task.isCancelled {
        onCleaned(cleaned)
        FeatureDiagnostics.record(
          .speechFinalization, .completed,
          durationMs: Int((CFAbsoluteTimeGetCurrent() - cleanupStarted) * 1_000)
        )
      } else if !Task.isCancelled {
        FeatureDiagnostics.record(.speechFinalization, .fallback)
      }
    } else {
      onCleaned(source)
    }

    guard !Task.isCancelled, options.target != .original else {
      return nil
    }
    let translateStarted = CFAbsoluteTimeGetCurrent()
    let translation = await self.processVoiceChunks(cleaned ?? source, options: options)
    if translation != nil {
      FeatureDiagnostics.record(
        .voiceOutput, .completed,
        durationMs: Int((CFAbsoluteTimeGetCurrent() - translateStarted) * 1_000)
      )
      FeatureDiagnostics.record(
        .conversation, .completed,
        durationMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1_000)
      )
    }
    return translation
  }

  private func processVoiceChunks(
    _ input: String, options: VoiceOutputConfiguration
  ) async -> String? {
    var output = ""
    for chunk in MeetingTranslationPolicy.chunks(input) {
      guard !Task.isCancelled else {
        FeatureDiagnostics.record(.voiceOutput, .cancelled)
        return nil
      }
      guard let processed = await self.processVoiceChunk(chunk, options: options) else { return nil }
      output = MeetingTranslationPolicy.combined(output, next: processed)
    }
    guard !Task.isCancelled else {
      FeatureDiagnostics.record(.voiceOutput, .cancelled)
      return nil
    }
    return output.isEmpty ? nil : output
  }

  /// The meeting record owns progress and persistence. Only the existing
  /// text-model coordinator owns inference. A failed chunk leaves saved source
  /// and previously confirmed translation chunks intact for explicit resume.
  func translateMeetingChunks(
    _ chunks: [String], startingAt index: Int, options: VoiceOutputConfiguration,
    onTranslated: @MainActor (Int, String) -> Bool
  ) async -> Bool {
    guard options.target != .original, index >= 0, index < chunks.count else { return false }
    self.lastVoiceOutputIssue = nil
    FeatureDiagnostics.record(.meetingTranslation, .started)
    guard let backgroundTask = await self.beginVoiceProcessing() else {
      FeatureDiagnostics.record(.meetingTranslation, .failed)
      return false
    }
    defer { self.endVoiceProcessing(backgroundTask) }
    for current in index..<chunks.count {
      guard !Task.isCancelled else {
        FeatureDiagnostics.record(.meetingTranslation, .cancelled)
        return false
      }
      guard let translated = await self.processVoiceChunk(chunks[current], options: options) else {
        FeatureDiagnostics.record(
          .meetingTranslation, Task.isCancelled ? .cancelled : .failed
        )
        return false
      }
      let displayed = CantoneseOutput.normalizeForOutput(translated, options: options)
      guard !Task.isCancelled, onTranslated(current + 1, displayed) else {
        if !Task.isCancelled {
          self.lastVoiceOutputIssue = "Unable to save the translated section locally."
        }
        FeatureDiagnostics.record(
          .meetingTranslation, Task.isCancelled ? .cancelled : .failed
        )
        return false
      }
    }
    FeatureDiagnostics.record(.meetingTranslation, .completed)
    return true
  }

  private func beginVoiceProcessing() async -> UIBackgroundTaskIdentifier? {
    guard !self.isProcessing, self.speechService?.canBeginTextWork != false else {
      self.lastVoiceOutputIssue = "The text model is busy. Try again when the current task finishes."
      FeatureDiagnostics.record(.voiceOutput, .blocked, failureReason: .busy)
      return nil
    }
    guard let downloads = self.downloadService, downloads.hasUsableModel else {
      self.lastVoiceOutputIssue = "No usable text model is selected. Check Settings → Text Model."
      FeatureDiagnostics.record(.voiceOutput, .unavailable, failureReason: .noTextModel)
      return nil
    }
    let settings = SharedSettings()
    let variant = settings.selectedLLMVariant
    guard let modelPath = downloads.modelFileURL(for: variant)?.path else {
      self.lastVoiceOutputIssue = "The selected text model file is missing."
      FeatureDiagnostics.record(.voiceOutput, .unavailable, failureReason: .missingModelFile)
      return nil
    }
    self.isProcessing = true
    settings.isLLMProcessing = true
    let backgroundTask = self.beginInferenceBackgroundTask()
    await self.prepareForInference(variant: variant, modelPath: modelPath)
    guard !Task.isCancelled, self.inferenceService.loadState == .loaded else {
      if !Task.isCancelled {
        self.lastVoiceOutputIssue = "The text model could not load. Check available memory."
      }
      FeatureDiagnostics.record(
        .voiceOutput, Task.isCancelled ? .cancelled : .failed,
        failureReason: Task.isCancelled ? nil : .modelLoadFailed
      )
      self.endVoiceProcessing(backgroundTask)
      return nil
    }
    return backgroundTask
  }

  private func endVoiceProcessing(_ backgroundTask: UIBackgroundTaskIdentifier) {
    self.inferenceService.unloadModel()
    SharedSettings().isLLMProcessing = false
    self.isProcessing = false
    self.endInferenceBackgroundTask(backgroundTask)
  }

  private func processVoiceChunk(
    _ input: String, options: VoiceOutputConfiguration
  ) async -> String? {
    var result: String?
    for attempt in 1...VoiceOutputPrompt.maximumTranslationAttempts {
      guard !Task.isCancelled else { return nil }
      result = await self.runInferenceWithTimeout(
        systemPrompt: attempt == 1 ? VoiceOutputPrompt.compactPrompt(for: options)
          : VoiceOutputPrompt.retryPrompt(for: options),
        userText: input, assistantPrefill: "",
        maxOutputTokens: min(512, max(192, input.utf8.count * 2))
      )
      guard !Task.isCancelled else { return nil }
      if let candidate = result?.trimmingCharacters(in: .whitespacesAndNewlines),
         !candidate.isEmpty,
         VoiceLanguageValidator.matches(candidate, target: options.target),
         (input.count < 30 || candidate.count <= max(input.count * 4, input.count + 200)) {
        self.lastVoiceOutputIssue = nil
        return CantoneseOutput.normalizeForOutput(candidate, options: options)
      }
      if attempt < VoiceOutputPrompt.maximumTranslationAttempts {
        FeatureDiagnostics.record(.voiceOutput, .fallback)
      }
    }
    guard !Task.isCancelled else {
      FeatureDiagnostics.record(.voiceOutput, .cancelled)
      return nil
    }
    guard let output = result?.trimmingCharacters(in: .whitespacesAndNewlines),
          !output.isEmpty else {
      self.lastVoiceOutputIssue = "The text model returned no usable result. Retry or choose a different Text Model."
      FeatureDiagnostics.record(.voiceOutput, .failed, failureReason: .inferenceUnavailable)
      return nil
    }
    guard VoiceLanguageValidator.matches(output, target: options.target) else {
      self.lastVoiceOutputIssue = "The result was not in the requested language. Try another Text Model."
      FeatureDiagnostics.record(.voiceOutput, .rejected, failureReason: .invalidTargetLanguage)
      return nil
    }
    if input.count >= 30, output.count > max(input.count * 4, input.count + 200) {
      self.lastVoiceOutputIssue = "The model output was unexpectedly long. Retry with another Text Model."
      FeatureDiagnostics.record(.voiceOutput, .rejected, failureReason: .oversizedOutput)
      return nil
    }
    // All output consumers share the same target-specific script formatting.
    self.lastVoiceOutputIssue = nil
    return CantoneseOutput.normalizeForOutput(output, options: options)
  }

  private func handleProcessingRequest() async {
    guard let request = LLMBridge.readRequest() else { return }
    guard !self.isProcessing, self.speechService?.isStopping != true,
          self.speechService?.canBeginTextWork != false else {
      LLMBridge.writeStatus(.busy, requestID: request.requestID)
      LLMBridge.clearRequest(matching: request.requestID)
      FeatureDiagnostics.record(.aiActions, .blocked,
        operationID: request.requestID.uuidString, phase: .busy)
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
      return
    }
    FeatureDiagnostics.record(.aiActions, .started)
    DiagnosticLog.write("llm: request received")

    guard !SharedSettings().isDictationLocked else {
      FeatureDiagnostics.record(.aiActions, .blocked)
      LLMBridge.writeStatus(.rejected, requestID: request.requestID)
      LLMBridge.clearRequest(matching: request.requestID)
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
      return
    }

    self.isProcessing = true
    let settings = SharedSettings()
    settings.isLLMProcessing = true
    LLMBridge.writeStatus(.accepted, requestID: request.requestID)
    FeatureDiagnostics.record(.aiActions, .queued,
      operationID: request.requestID.uuidString, phase: .accepted)
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingStarted)
    let stylingHost = OnboardingTextEntry.stylingHost(settings.hostBundleId)

    defer {
      self.isProcessing = false
      settings.isLLMProcessing = false
      let terminalPhase = LLMBridge.readStatus(matching: request.requestID)?.phase
      if terminalPhase?.isTerminal != true {
        LLMBridge.writeStatus(.failed, requestID: request.requestID)
      }
      LLMBridge.clearRequest(matching: request.requestID)
      // Success already sent its completion event; never report it as a failure.
      if terminalPhase != .completed {
        TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
      }
    }

    guard let validated = self.validateRequest(settings: settings, request: request) else { return }

    let bgTaskID = self.beginInferenceBackgroundTask()
    defer { self.endInferenceBackgroundTask(bgTaskID) }

    await self.prepareForInference(variant: validated.variant, modelPath: validated.modelPath)

    guard self.inferenceService.loadState == .loaded else {
      let state = String(describing: self.inferenceService.loadState)
      FeatureDiagnostics.record(.aiActions, .failed)
      DiagnosticLog.write("llm: load failed, state=\(state)")
      return
    }
    DiagnosticLog.write("llm: model loaded")

    let systemPrompt = self.buildSystemPrompt(for: validated.request, settings: settings)
    let prefill = validated.request.action.continuesInput ? validated.request.text : ""
    let result = await self.runInferenceWithTimeout(
      systemPrompt: systemPrompt,
      userText: validated.request.text,
      assistantPrefill: prefill,
    )

    if let result, !result.isEmpty {
      if validated.request.action == .translate,
         let rawTarget = validated.request.translationTarget,
         let target = VoiceOutputTarget(rawValue: rawTarget),
         !VoiceLanguageValidator.matches(result, target: target) {
        FeatureDiagnostics.record(.aiActions, .rejected)
        self.inferenceService.unloadModel()
        return
      }
      let finalResult = self.styled(result, action: validated.request.action, host: stylingHost, settings: settings)
      if LLMBridge.writeResult(finalResult, requestID: validated.request.requestID) {
        TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingComplete)
        FeatureDiagnostics.record(.aiActions, .completed)
        DiagnosticLog.write("llm: complete, result=\(finalResult.count) chars")
      } else {
        FeatureDiagnostics.record(.aiActions, .failed)
        DiagnosticLog.write("llm: result could not be saved in shared storage")
      }
    } else {
      FeatureDiagnostics.record(.aiActions, .failed)
      DiagnosticLog.write("llm: FAILED, inference produced nothing")
    }

    self.inferenceService.unloadModel()
  }

  private func validateRequest(settings: SharedSettings, request: LLMRequest) -> ValidatedRequest? {
    settings.synchronize()
    if request.action == .translate {
      guard let rawTarget = request.translationTarget,
            let target = VoiceOutputTarget(rawValue: rawTarget), target != .original,
            target.targetInstruction(customLanguage: request.customTranslationLanguage ?? "") != nil else {
        return nil
      }
    }
    DiagnosticLog.write("llm: text=\(request.text.count) chars, action=\(request.action.rawValue)")

    guard let downloadService = self.downloadService, downloadService.hasUsableModel else {
      DiagnosticLog.write("llm: no usable model, selected=\(settings.selectedLLMVariant.rawValue)")
      return nil
    }

    let variant = settings.selectedLLMVariant
    guard let modelPath = downloadService.modelFileURL(for: variant)?.path else {
      DiagnosticLog.write("llm: model file missing for \(variant.rawValue)")
      return nil
    }
    DiagnosticLog.write("llm: variant=\(variant.rawValue), template=\(variant.chatTemplate.rawValue)")

    return ValidatedRequest(request: request, modelPath: modelPath, variant: variant)
  }

  private func beginInferenceBackgroundTask() -> UIBackgroundTaskIdentifier {
    var bgTaskID = UIBackgroundTaskIdentifier.invalid
    bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "LLMInference") {
      DiagnosticLog.write("llm: background task EXPIRED — suspension imminent")
      UIApplication.shared.endBackgroundTask(bgTaskID)
      bgTaskID = .invalid
    }
    let remaining = UIApplication.shared.backgroundTimeRemaining
    let budget = remaining < .greatestFiniteMagnitude ? "\(Int(remaining))s" : "unlimited"
    DiagnosticLog.write("llm: bg task started, budget=\(budget)")
    return bgTaskID
  }

  private func endInferenceBackgroundTask(_ taskID: UIBackgroundTaskIdentifier) {
    if taskID != .invalid {
      UIApplication.shared.endBackgroundTask(taskID)
    }
  }

  private func prepareForInference(variant: LLMModelVariant, modelPath: String) async {
    if let speechService = self.speechService {
      guard await speechService.unloadForLLMProcessing() else { return }
    }

    if self.inferenceService.loadState != .loaded {
      await self.inferenceService.loadModel(variant: variant, path: modelPath)
    }
  }

  private func styled(_ text: String, action: LLMAction, host: String?, settings: SharedSettings) -> String {
    guard action != .translate, action != .addPunctuation, action != .fixGrammar else { return text }
    let resolvedStyle = AppStyleStore().resolvedStyle(
      hostBundleId: host,
      defaultStyle: settings.defaultWritingStyle,
    )
    return TextStyleFormatter.format(text, style: resolvedStyle)
  }

  private func buildSystemPrompt(for request: LLMRequest, settings: SharedSettings) -> String {
    if request.action == .translate, let rawTarget = request.translationTarget,
       let target = VoiceOutputTarget(rawValue: rawTarget) {
      return VoiceOutputPrompt.systemPrompt(for: VoiceOutputConfiguration(
        cleanupEnabled: false, target: target, register: .faithful,
        customLanguage: request.customTranslationLanguage ?? ""
      ))
    }
    let language = request.language
    if
      let customId = request.customPromptId,
      let custom = settings.llmCustomPrompts.first(where: { $0.id == customId })
    {
      return LLMPromptTemplates.systemPrompt(for: custom, language: language)
    }
    return LLMPromptTemplates.systemPrompt(for: request.action, language: language)
  }

  /// The native generation loop already checks an absolute per-call deadline.
  /// Do not race a second TaskGroup timer against an unstructured inference
  /// task: that allowed the model/context to be unloaded before decode ended.
  private func runInferenceWithTimeout(
    systemPrompt: String,
    userText: String,
    assistantPrefill: String,
    maxOutputTokens: Int? = nil
  ) async -> String? {
    let remaining = UIApplication.shared.backgroundTimeRemaining
    let foregroundBudget: TimeInterval =
      SharedSettings().selectedLLMVariant == .hereticLarge ? 110 : 75
    let deadline = remaining < .greatestFiniteMagnitude
      ? min(foregroundBudget, max(0, remaining - Self.safetyMarginSeconds))
      : foregroundBudget
    guard deadline >= 5, !Task.isCancelled else { return nil }
    return await self.inferenceService.process(
      systemPrompt: systemPrompt, userText: userText,
      assistantPrefill: assistantPrefill, maxOutputTokens: maxOutputTokens,
      deadlineSeconds: deadline
    )
  }

}



