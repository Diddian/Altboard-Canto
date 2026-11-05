
import Foundation

import UIKit

@MainActor
final class LLMProcessingCoordinator: ObservableObject {

  let inferenceService = LLMInferenceService()

  weak var speechService: SpeechRecognitionService?
  weak var downloadService: LLMDownloadService?

  @Published private(set) var isProcessing = false

  func setupObservers() {
    self.requestObserver = TranscriptionBridge.observeDarwinNotification(
      DarwinNotificationName.requestLLMProcessing
    ) { [weak self] in
      Task { @MainActor [weak self] in
        let tokenSettings = SharedSettings()
        tokenSettings.synchronize()
        guard tokenSettings.dictationSessionToken != nil else {
          return
        }
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
  func processVoiceDictation(_ input: String, options: VoiceOutputConfiguration) async -> String? {
    guard options.needsLLM, !input.isEmpty else { return nil }
    let started = CFAbsoluteTimeGetCurrent()
    FeatureDiagnostics.record(.voiceOutput, .started)
    guard !self.isProcessing else {
      FeatureDiagnostics.record(.voiceOutput, .blocked)
      DiagnosticLog.write("voice/llm: already processing")
      return nil
    }
    guard let downloads = self.downloadService, downloads.hasUsableModel else {
      FeatureDiagnostics.record(.voiceOutput, .unavailable)
      DiagnosticLog.write("voice/llm: offline text model unavailable")
      return nil
    }
    let settings = SharedSettings()
    let variant = settings.selectedLLMVariant
    guard let modelPath = downloads.modelFileURL(for: variant)?.path else {
      FeatureDiagnostics.record(.voiceOutput, .unavailable)
      DiagnosticLog.write("voice/llm: selected model file missing")
      return nil
    }
    self.isProcessing = true
    settings.isLLMProcessing = true
    defer {
      self.inferenceService.unloadModel()
      settings.isLLMProcessing = false
      self.isProcessing = false
    }
    let backgroundTask = self.beginInferenceBackgroundTask()
    defer { self.endInferenceBackgroundTask(backgroundTask) }
    await self.prepareForInference(variant: variant, modelPath: modelPath)
    guard self.inferenceService.loadState == .loaded else {
      FeatureDiagnostics.record(.voiceOutput, .failed)
      DiagnosticLog.write("voice/llm: offline model load failed")
      return nil
    }
    let result = await self.runInferenceWithTimeout(
      systemPrompt: VoiceOutputPrompt.systemPrompt(for: options),
      userText: input, assistantPrefill: ""
    )
    guard let output = result?.trimmingCharacters(in: .whitespacesAndNewlines), !output.isEmpty else {
      FeatureDiagnostics.record(.voiceOutput, .failed)
      DiagnosticLog.write("voice/llm: output missing or timed out")
      return nil
    }
    guard VoiceLanguageValidator.matches(output, target: options.target) else {
      FeatureDiagnostics.record(.voiceOutput, .rejected)
      DiagnosticLog.write("voice/llm: generated text did not match selected language")
      return nil
    }
    if input.count >= 30, output.count > max(input.count * 4, input.count + 200) {
      FeatureDiagnostics.record(.voiceOutput, .rejected)
      DiagnosticLog.write("voice/llm: output excessively long")
      return nil
    }
    FeatureDiagnostics.record(.voiceOutput, .completed,
      durationMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1_000))
    DictationBreadcrumb.record(
      "voice/llm: complete in \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - started))s"
    )
    return output
  }

  private func handleProcessingRequest() async {
    guard !self.isProcessing else {
      FeatureDiagnostics.record(.aiActions, .blocked)
      DiagnosticLog.write("llm: request ignored, already processing")
      return
    }
    FeatureDiagnostics.record(.aiActions, .started)
    DiagnosticLog.write("llm: request received")

    guard !SharedSettings().isDictationLocked else {
      FeatureDiagnostics.record(.aiActions, .blocked)
      LLMBridge.clearRequest()
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
      return
    }

    self.isProcessing = true
    let settings = SharedSettings()
    settings.isLLMProcessing = true
    TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingStarted)
    let stylingHost = OnboardingTextEntry.stylingHost(settings.hostBundleId)

    defer {
      self.isProcessing = false
      settings.isLLMProcessing = false
      LLMBridge.clearRequest()
    }

    guard let validated = self.validateRequest(settings: settings) else { return }

    let bgTaskID = self.beginInferenceBackgroundTask()
    defer { self.endInferenceBackgroundTask(bgTaskID) }

    await self.prepareForInference(variant: validated.variant, modelPath: validated.modelPath)

    guard self.inferenceService.loadState == .loaded else {
      let state = String(describing: self.inferenceService.loadState)
      FeatureDiagnostics.record(.aiActions, .failed)
      DiagnosticLog.write("llm: load failed, state=\(state)")
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
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
        TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
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
        TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
      }
    } else {
      FeatureDiagnostics.record(.aiActions, .failed)
      DiagnosticLog.write("llm: FAILED, inference produced nothing")
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
    }

    self.inferenceService.unloadModel()
  }

  private func validateRequest(settings: SharedSettings) -> ValidatedRequest? {
    settings.synchronize()
    guard let request = LLMBridge.readRequest() else {
      DiagnosticLog.write("llm: no request in bridge")
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
      return nil
    }
    if request.action == .translate {
      guard let rawTarget = request.translationTarget,
            let target = VoiceOutputTarget(rawValue: rawTarget), target != .original,
            target.targetInstruction(customLanguage: request.customTranslationLanguage ?? "") != nil else {
        TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
        return nil
      }
    }
    DiagnosticLog.write("llm: text=\(request.text.count) chars, action=\(request.action.rawValue)")

    guard let downloadService = self.downloadService, downloadService.hasUsableModel else {
      DiagnosticLog.write("llm: no usable model, selected=\(settings.selectedLLMVariant.rawValue)")
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
      return nil
    }

    let variant = settings.selectedLLMVariant
    guard let modelPath = downloadService.modelFileURL(for: variant)?.path else {
      DiagnosticLog.write("llm: model file missing for \(variant.rawValue)")
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingFailed)
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
      await speechService.unloadForLLMProcessing()
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

  private func runInferenceWithTimeout(
    systemPrompt: String,
    userText: String,
    assistantPrefill: String
  ) async -> String? {
    let remaining = UIApplication.shared.backgroundTimeRemaining
    let timeout: TimeInterval =
      if remaining < .greatestFiniteMagnitude {
        max(remaining - Self.safetyMarginSeconds, 10)
      } else {
        Self.inferenceTimeoutSeconds
      }

    let generationDeadline = min(
      timeout, SharedSettings().selectedLLMVariant == .hereticLarge ? 60.0 : 15.0
    )

    return await withTaskGroup(of: String?.self) { group in
      group.addTask {
        await self.inferenceService.process(
          systemPrompt: systemPrompt,
          userText: userText,
          assistantPrefill: assistantPrefill,
          maxOutputTokens: nil,
          deadlineSeconds: generationDeadline,
        )
      }

      group.addTask {
        try? await Task.sleep(for: .seconds(timeout))
        return nil
      }

      if let result = await group.next() {
        group.cancelAll()
        return result
      }

      group.cancelAll()
      return nil
    }
  }
}


