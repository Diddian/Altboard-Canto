import Foundation
import SherpaOnnx

enum Qwen3ModelBundle {
  static let required = ["conv_frontend.onnx", "tokenizer/vocab.json", "tokenizer/merges.txt", "tokenizer/tokenizer_config.json"]
  static func locate(in root: URL) -> URL? {
    let fm = FileManager.default
    guard fm.fileExists(atPath: root.path) else { return nil }
    let candidates = [root] + ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
    return candidates.first { directory in
      required.allSatisfy { fm.fileExists(atPath: directory.appendingPathComponent($0).path) }
        && ((try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
          .contains { $0.lastPathComponent.hasPrefix("encoder") && $0.pathExtension == "onnx" }
        && ((try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
          .contains { $0.lastPathComponent.hasPrefix("decoder") && $0.pathExtension == "onnx" }
    }
  }
  static func isValid(directory: URL) -> Bool { locate(in: directory) != nil }
  static func file(prefix: String, in directory: URL) -> String? {
    ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
      .first { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "onnx" }?.path
  }
}

@MainActor
final class Qwen3TranscriptionService: ObservableObject {
  @Published private(set) var loadState: ModelLoadState = .unloaded
  private var recognizer: SherpaOnnxOfflineRecognizer?

  func loadModel(from url: URL) async {
    self.loadState = .loading
    guard let folder = Qwen3ModelBundle.locate(in: url),
          let encoder = Qwen3ModelBundle.file(prefix: "encoder", in: folder),
          let decoder = Qwen3ModelBundle.file(prefix: "decoder", in: folder) else {
      self.loadState = .error("Qwen3 ONNX bundle files missing")
      return
    }
    let model = sherpaOnnxOfflineQwen3ASRModelConfig(
      convFrontend: folder.appendingPathComponent("conv_frontend.onnx").path,
      encoder: encoder, decoder: decoder,
      tokenizer: folder.appendingPathComponent("tokenizer").path)
    let conf = sherpaOnnxOfflineModelConfig(tokens: "", numThreads: 2, provider: "cpu", qwen3Asr: model)
    var config = sherpaOnnxOfflineRecognizerConfig(featConfig: sherpaOnnxFeatureConfig(), modelConfig: conf)
    self.recognizer = SherpaOnnxOfflineRecognizer(config: &config)
    self.loadState = .loaded
  }

  func waitForLoad() async {}
  func unloadModel() { recognizer = nil; loadState = .unloaded }
  func transcribe(audioSamples: [Float]) async -> TranscriptionResult {
    guard let recognizer, !audioSamples.isEmpty else { return .failed("Qwen3 model unavailable") }
    let output = recognizer.decode(samples: audioSamples, sampleRate: 16_000).text
    guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .noSpeech }
    return .text(TranscriptionOutput(text: output, firstWordStart: nil, lastWordEnd: nil))
  }
}
