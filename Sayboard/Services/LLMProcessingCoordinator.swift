
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

  /// Edit the speech transcript in the main app before it reaches the keyboard.
  /// If the model is unavailable or fails, the original transcription survives.
  func processVoiceDictation(_ input: String, compose: Bool = false) async -> String? {
    let settings = SharedSettings()
    let options = settings.voiceOutputConfiguration
    guard (options.needsLLM || compose), !input.isEmpty else { return nil }
    let started = CFAbsoluteTimeGetCurrent()
    DictationBreadcrumb.record(compose ? "llm: voice composition requested" : "llm: voice cleanup requested")
    guard !self.isProcessing else {
      DiagnosticLog.write("voice/llm: already processing; use raw transcription")
      return nil
    }
    guard let downloads = self.downloadService, downloads.hasUsableModel else {
      DiagnosticLog.write("voice/llm: offline LLM not downloaded; use raw transcription")
      return nil
    }
    let variant = settings.selectedLLMVariant
    guard let modelPath = downloads.modelFileURL(for: variant)?.path else {
      DiagnosticLog.write("voice/llm: selected model file missing; use raw transcription")
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
    let prepareDuration = CFAbsoluteTimeGetCurrent() - started
    DictationBreadcrumb.record("llm: prepare finished in \(String(format: "%.1f", prepareDuration))s")
    guard self.inferenceService.loadState == .loaded else {
      DiagnosticLog.write("voice/llm: model failed to load; use raw transcription")
      return nil
    }

    let prompt = compose
      ? VoiceComposePrompt.systemPrompt(for: options, instruction: input)
      : VoiceOutputPrompt.systemPrompt(for: options)
    var result = await self.runInferenceWithTimeout(
      systemPrompt: prompt,
      userText: input,
      assistantPrefill: "",
      forComposition: compose
    )
    // Repair obviously wrong-language output only; avoid paying for two LLM passes normally.
    if let first = result, VoiceComposePrompt.needsCantoneseRepair(first, target: options.target) {
      DictationBreadcrumb.record("llm: retrying incorrect English-only Cantonese output")
      let repaired = await self.runInferenceWithTimeout(
        systemPrompt: VoiceComposePrompt.cantoneseRepairPrompt,
        userText: first,
        assistantPrefill: ""
      )
      if let repaired, !VoiceComposePrompt.needsCantoneseRepair(repaired, target: options.target) {
        result = repaired
      }
    }
    DictationBreadcrumb.record(
      "llm: generation took \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - started - prepareDuration))s"
    )

    guard let result, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      DiagnosticLog.write("voice/llm: empty or timed out; use raw transcription")
      return nil
    }

    let output = result.trimmingCharacters(in: .whitespacesAndNewlines)
    if !compose && input.count >= 30 && output.count > max(input.count * 4, input.count + 200) {
      DiagnosticLog.write("voice/llm: excessive output; use raw transcription")
      return nil
    }
    DiagnosticLog.write("voice/llm: processed \(input.count) to \(output.count) characters")
    DictationBreadcrumb.record("llm: cleanup complete in \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - started))s; \(input.count) to \(output.count) chars")
    return output
  }

  private func handleProcessingRequest() async {
    guard !self.isProcessing else {
      DiagnosticLog.write("llm: request ignored, already processing")
      return
    }
    DiagnosticLog.write("llm: request received")

    guard !SharedSettings().isDictationLocked else {
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
      let finalResult = self.styled(result, action: validated.request.action, host: stylingHost, settings: settings)
      LLMBridge.writeResult(finalResult)
      TranscriptionBridge.postDarwinNotification(DarwinNotificationName.llmProcessingComplete)
      DiagnosticLog.write("llm: complete, result=\(finalResult.count) chars")
    } else {
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
    guard action != .addPunctuation, action != .fixGrammar else { return text }
    let resolvedStyle = AppStyleStore().resolvedStyle(
      hostBundleId: host,
      defaultStyle: settings.defaultWritingStyle,
    )
    return TextStyleFormatter.format(text, style: resolvedStyle)
  }

  private func buildSystemPrompt(for request: LLMRequest, settings: SharedSettings) -> String {
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
    assistantPrefill: String,
    forComposition: Bool = false,
  ) async -> String? {
    let remaining = UIApplication.shared.backgroundTimeRemaining
    let timeout: TimeInterval =
      if remaining < .greatestFiniteMagnitude {
        max(remaining - Self.safetyMarginSeconds, 10)
      } else {
        Self.inferenceTimeoutSeconds
      }

    return await withTaskGroup(of: String?.self) { group in
      group.addTask {
        await self.inferenceService.process(
          systemPrompt: systemPrompt,
          userText: userText,
          assistantPrefill: assistantPrefill,
          maxOutputTokens: forComposition ? 512 : nil,
          deadlineSeconds: forComposition ? 40 : 15,
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
