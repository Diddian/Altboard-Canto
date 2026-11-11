import Foundation
import SherpaOnnxShared

private struct SenseVoiceRecognizerHandle: @unchecked Sendable {
  let value: SherpaOnnxOfflineRecognizer
}

@MainActor
final class SenseVoiceTranscriptionService: ObservableObject {
  @Published private(set) var loadState: ModelLoadState = .unloaded
  private var recognizer: SenseVoiceRecognizerHandle?
  private var loadTask: Task<SenseVoiceRecognizerHandle, Never>?
  private var generation = 0

  func loadModel(from directory: URL) async {
    if let loadTask {
      let token = self.generation
      let value = await loadTask.value
      self.finish(value, generation: token)
      return
    }
    guard let folder = SenseVoiceModelBundle.locate(in: directory) else {
      FeatureDiagnostics.record(.speechModel, .failed)
      self.loadState = .error("SenseVoice model files are missing or not verified")
      return
    }
    self.loadState = .loading
    self.generation += 1
    let token = self.generation
    let started = CFAbsoluteTimeGetCurrent()
    let modelPath = folder.appendingPathComponent("model.int8.onnx").path
    let tokensPath = folder.appendingPathComponent("tokens.txt").path
    let load = Task.detached(priority: .userInitiated) { () -> SenseVoiceRecognizerHandle in
      let model = sherpaOnnxOfflineSenseVoiceModelConfig(
        model: modelPath, language: "auto", useInverseTextNormalization: false
      )
      let config = sherpaOnnxOfflineModelConfig(
        tokens: tokensPath,
        numThreads: max(2, min(ProcessInfo.processInfo.activeProcessorCount - 1, 4)),
        provider: "cpu", senseVoice: model
      )
      var recognizerConfig = sherpaOnnxOfflineRecognizerConfig(
        featConfig: sherpaOnnxFeatureConfig(), modelConfig: config
      )
      return SenseVoiceRecognizerHandle(value: SherpaOnnxOfflineRecognizer(config: &recognizerConfig))
    }
    self.loadTask = load
    let loaded = await load.value
    self.finish(loaded, generation: token)
    FeatureDiagnostics.record(
      .speechModel, .completed,
      durationMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1_000),
      residentMB: ProcessFootprint.residentMB()
    )
  }

  func waitForLoad() async {
    guard let loadTask else { return }
    let token = self.generation
    let value = await loadTask.value
    self.finish(value, generation: token)
  }

  private func finish(_ value: SenseVoiceRecognizerHandle, generation: Int) {
    guard generation == self.generation, self.loadState == .loading else { return }
    self.recognizer = value
    self.loadTask = nil
    self.loadState = .loaded
  }

  func unloadModel() {
    self.generation += 1
    self.loadTask?.cancel()
    self.loadTask = nil
    self.recognizer = nil
    self.loadState = .unloaded
  }

  func transcribe(audioSamples: [Float]) async -> TranscriptionResult {
    guard let recognizer = self.recognizer, !audioSamples.isEmpty else {
      return .failed("SenseVoice speech model is not loaded")
    }
    let start = CFAbsoluteTimeGetCurrent()
    let result = await Task.detached(priority: .userInitiated) {
      recognizer.value.decode(samples: audioSamples, sampleRate: 16_000).text
    }.value
    let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)
    // The shared caller records speechDecode once. Do not double-count
    // throughput samples when this recognizer is selected.
    DictationBreadcrumb.record(
      "sensevoice: decode completed in \(elapsed)ms for \(audioSamples.count / 16)ms audio"
    )
    let cleaned = TextSanitizer.sanitize(result)
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? .noSpeech
      : .text(TranscriptionOutput(text: cleaned, firstWordStart: nil, lastWordEnd: nil))
  }
}

