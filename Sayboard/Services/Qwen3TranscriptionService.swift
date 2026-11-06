import Foundation
import SherpaOnnxShared

/// The recognizer wraps a native sherpa-onnx object. It must stay alive until decode finishes.
private struct QwenRecognizerHandle: @unchecked Sendable {
  let value: SherpaOnnxOfflineRecognizer
}

@MainActor
final class Qwen3TranscriptionService: ObservableObject {
  @Published private(set) var loadState: ModelLoadState = .unloaded
  private var recognizer: QwenRecognizerHandle?
  private var loadTask: Task<QwenRecognizerHandle, Never>?
  private var loadGeneration = 0

  func loadModel(from url: URL) async {
    if let existing = self.loadTask {
      let generation = self.loadGeneration
      let loaded = await existing.value
      self.finishLoading(loaded, generation: generation)
      return
    }
    self.loadState = .loading
    let loadStarted = CFAbsoluteTimeGetCurrent()
    DictationBreadcrumb.record("qwen: validating model files")
    guard let folder = Qwen3ModelBundle.locate(in: url),
          let encoder = Qwen3ModelBundle.file(prefix: "encoder", in: folder),
          let decoder = Qwen3ModelBundle.file(prefix: "decoder", in: folder)
    else {
      self.loadState = .error("Missing sherpa-onnx Qwen3 model files")
      DictationBreadcrumb.record("qwen: missing ONNX or tokenizer files")
      return
    }

    self.loadGeneration += 1
    let generation = self.loadGeneration
    let frontend = folder.appendingPathComponent("conv_frontend.onnx").path
    let tokenizer = folder.appendingPathComponent("tokenizer").path
    let task = Task.detached(priority: .userInitiated) { () -> QwenRecognizerHandle in
      DictationBreadcrumb.record("qwen: native ONNX recognizer initialization started")
      let model = sherpaOnnxOfflineQwen3ASRModelConfig(
        convFrontend: frontend,
        encoder: encoder,
        decoder: decoder,
        tokenizer: tokenizer,
        maxTotalLen: 512,
        // Permit longer Cantonese speech; EOS still stops short answers early.
        maxNewTokens: 256
      )
      let configuration = sherpaOnnxOfflineModelConfig(
        // Four CPU threads on a six-core device; keep two on smaller CPUs.
        tokens: "", numThreads: max(2, min(ProcessInfo.processInfo.activeProcessorCount - 1, 4)),
        provider: "cpu", qwen3Asr: model
      )
      var config = sherpaOnnxOfflineRecognizerConfig(
        featConfig: sherpaOnnxFeatureConfig(), modelConfig: configuration
      )
      let recognizer = SherpaOnnxOfflineRecognizer(config: &config)
      DictationBreadcrumb.record("qwen: native recognizer created")
      return QwenRecognizerHandle(value: recognizer)
    }
    self.loadTask = task
    let loaded = await task.value
    guard generation == self.loadGeneration else { return }
    self.finishLoading(loaded, generation: generation)
    DictationBreadcrumb.record(
      "qwen: model loaded in \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - loadStarted))s"
    )
  }

  /// Stop can wait on the detached native initializer before the original
  /// loadModel task resumes on MainActor. Finalize from either waiter safely.
  func waitForLoad() async {
    guard let loading = self.loadTask else { return }
    let generation = self.loadGeneration
    let loaded = await loading.value
    self.finishLoading(loaded, generation: generation)
  }

  private func finishLoading(_ loaded: QwenRecognizerHandle, generation: Int) {
    guard generation == self.loadGeneration, self.loadState == .loading else { return }
    self.recognizer = loaded
    self.loadTask = nil
    self.loadState = .loaded
  }

  func unloadModel() {
    self.loadGeneration += 1
    self.loadTask?.cancel()
    self.loadTask = nil
    self.recognizer = nil
    self.loadState = .unloaded
  }

  func transcribe(audioSamples: [Float]) async -> TranscriptionResult {
    guard let recognizer = self.recognizer, !audioSamples.isEmpty else {
      return .failed("Qwen3 speech model is not loaded")
    }
    let started = CFAbsoluteTimeGetCurrent()
    DictationBreadcrumb.record("qwen: decode started, \(audioSamples.count / 16_000)s audio")
    let text = await Task.detached(priority: .userInitiated) {
      recognizer.value.decode(samples: audioSamples, sampleRate: 16_000).text
    }.value
    DictationBreadcrumb.record(
      "qwen: decode completed in \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - started))s, \(text.count) chars"
    )
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .noSpeech }
    return .text(TranscriptionOutput(text: text, firstWordStart: nil, lastWordEnd: nil))
  }
}
