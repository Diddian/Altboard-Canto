import Foundation
import SherpaOnnx

enum Qwen3ModelBundle {
  static let required = [
    "conv_frontend.onnx",
    "tokenizer/vocab.json",
    "tokenizer/merges.txt",
    "tokenizer/tokenizer_config.json",
  ]

  static func locate(in root: URL) -> URL? {
    let fm = FileManager.default
    guard fm.fileExists(atPath: root.path) else { return nil }
    let candidates = [root] + ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
    return candidates.first { directory in
      required.allSatisfy { fm.fileExists(atPath: directory.appendingPathComponent($0).path) }
        && file(prefix: "encoder", in: directory) != nil
        && file(prefix: "decoder", in: directory) != nil
    }
  }

  static func isValid(directory: URL) -> Bool { locate(in: directory) != nil }

  static func file(prefix: String, in directory: URL) -> String? {
    let candidates = (try? FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil
    )) ?? []
    return candidates.first {
      $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "onnx"
    }?.path
  }
}

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
      _ = await existing.value
      return
    }
    self.loadState = .loading
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
        maxNewTokens: 128
      )
      let configuration = sherpaOnnxOfflineModelConfig(
        tokens: "", numThreads: 2, provider: "cpu", qwen3Asr: model
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
    self.recognizer = loaded
    self.loadTask = nil
    self.loadState = .loaded
    DictationBreadcrumb.record("qwen: model load state loaded")
  }

  func waitForLoad() async {
    if let loading = self.loadTask { _ = await loading.value }
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
    DictationBreadcrumb.record("qwen: decode started")
    let text = await Task.detached(priority: .userInitiated) {
      recognizer.value.decode(samples: audioSamples, sampleRate: 16_000).text
    }.value
    DictationBreadcrumb.record("qwen: decode completed")
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .noSpeech }
    return .text(TranscriptionOutput(text: text, firstWordStart: nil, lastWordEnd: nil))
  }
}
