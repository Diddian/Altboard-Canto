import Foundation
import llama

/// An independently owned multimodal handle. Detached decode tasks retain
/// it until their native work ends, even if the selected model changes.
private final class HKGGUFRecognizerHandle: @unchecked Sendable {
  let model: OpaquePointer
  let context: OpaquePointer
  let audio: OpaquePointer

  init(model: OpaquePointer, context: OpaquePointer, audio: OpaquePointer) {
    self.model = model
    self.context = context
    self.audio = audio
  }

  deinit {
    mtmd_free(audio)
    llama_free(context)
    llama_model_free(model)
  }
}

@MainActor
final class HKCantoneseGGUFTranscriptionService: ObservableObject {
  @Published private(set) var loadState: ModelLoadState = .unloaded

  private var recognizer: HKGGUFRecognizerHandle?
  private var loadTask: Task<HKGGUFRecognizerHandle?, Never>?
  private var decodeTask: Task<String?, Never>?
  private var generation = 0

  func loadModel(from directory: URL) async {
    if let loadTask {
      let token = generation
      self.finishLoading(await loadTask.value, token: token)
      return
    }
    guard let folder = HKCantoneseGGUFModelBundle.locate(in: directory) else {
      loadState = .error("Hong Kong Qwen3 GGUF files have not been verified")
      FeatureDiagnostics.record(.speechModel, .failed)
      return
    }
    generation += 1
    let token = generation
    loadState = .loading
    let start = CFAbsoluteTimeGetCurrent()
    let modelPath = folder.appendingPathComponent(HKCantoneseGGUFModelBundle.modelName).path
    let audioPath = folder.appendingPathComponent(HKCantoneseGGUFModelBundle.audioName).path
    let task = Task.detached(priority: .userInitiated) {
      Self.initialize(modelPath: modelPath, audioPath: audioPath)
    }
    self.loadTask = task
    let loaded = await task.value
    self.finishLoading(loaded, token: token)
    FeatureDiagnostics.record(
      .speechModel, loaded == nil ? .failed : .completed,
      durationMs: Int((CFAbsoluteTimeGetCurrent() - start) * 1_000),
      residentMB: ProcessFootprint.residentMB()
    )
  }

  func waitForLoad() async {
    guard let loadTask else { return }
    let token = generation
    self.finishLoading(await loadTask.value, token: token)
  }

  private func finishLoading(_ value: HKGGUFRecognizerHandle?, token: Int) {
    guard token == generation, loadState == .loading else { return }
    loadTask = nil
    recognizer = value
    loadState = value == nil ? .error("Could not initialize Hong Kong Qwen3 audio model") : .loaded
  }

  func unloadModel() {
    generation += 1
    loadTask?.cancel()
    decodeTask?.cancel()
    loadTask = nil
    decodeTask = nil
    recognizer = nil
    loadState = .unloaded
  }

  func transcribe(audioSamples: [Float]) async -> TranscriptionResult {
    guard let recognizer, !audioSamples.isEmpty else {
      return .failed("Hong Kong Qwen3 GGUF is not loaded")
    }
    guard decodeTask == nil else { return .failed("Hong Kong Qwen3 is already decoding") }
    let started = CFAbsoluteTimeGetCurrent()
    let task = Task.detached(priority: .userInitiated) {
      Self.decode(recognizer: recognizer, samples: audioSamples)
    }
    decodeTask = task
    let output = await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
    if decodeTask != nil { decodeTask = nil }
    DictationBreadcrumb.record(
      "qwen-hk: decode \(Int((CFAbsoluteTimeGetCurrent() - started) * 1_000))ms, \(audioSamples.count / 16)ms audio"
    )
    guard !Task.isCancelled else { return .failed("Recognition cancelled") }
    guard let output else { return .failed("Hong Kong Qwen3 audio inference failed") }
    let cleaned = TextSanitizer.sanitize(output).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return .noSpeech }
    return .text(TranscriptionOutput(text: cleaned, firstWordStart: nil, lastWordEnd: nil))
  }

  private nonisolated static func initialize(
    modelPath: String, audioPath: String
  ) -> HKGGUFRecognizerHandle? {
    guard !Task.isCancelled else { return nil }
    llama_backend_init()
    var modelParams = llama_model_default_params()
    // CPU-only first: avoid peak Metal allocations during audio capture.
    modelParams.n_gpu_layers = 0
    guard let model = llama_model_load_from_file(modelPath, modelParams) else { return nil }
    var contextParams = llama_context_default_params()
    contextParams.n_ctx = 4096
    contextParams.n_batch = 1024
    contextParams.n_threads = Int32(max(2, min(ProcessInfo.processInfo.activeProcessorCount - 1, 4)))
    contextParams.n_threads_batch = contextParams.n_threads
    guard let context = llama_init_from_model(model, contextParams) else {
      llama_model_free(model)
      return nil
    }
    var audioParams = mtmd_context_params_default()
    audioParams.use_gpu = false
    audioParams.n_threads = contextParams.n_threads
    audioParams.warmup = false
    guard let audio = mtmd_init_from_file(audioPath, model, audioParams) else {
      llama_free(context)
      llama_model_free(model)
      return nil
    }
    guard mtmd_support_audio(audio), mtmd_get_audio_sample_rate(audio) == 16_000,
          !Task.isCancelled else {
      mtmd_free(audio)
      llama_free(context)
      llama_model_free(model)
      return nil
    }
    return HKGGUFRecognizerHandle(model: model, context: context, audio: audio)
  }

  private nonisolated static func decode(
    recognizer: HKGGUFRecognizerHandle, samples: [Float]
  ) -> String? {
    // Author's evaluation covers <=30 s; split recordings without loading
    // several overlapping native recognizers or retaining audio in logs.
    let maxSamples = 30 * 16_000
    var parts = [String]()
    var cursor = 0
    while cursor < samples.count {
      guard !Task.isCancelled else { return nil }
      let end = min(cursor + maxSamples, samples.count)
      guard let piece = Self.decodeChunk(recognizer: recognizer, samples: Array(samples[cursor..<end]))
      else { return nil }
      if !piece.isEmpty { parts.append(piece) }
      cursor = end
    }
    return parts.joined(separator: " ")
  }

  private nonisolated static func decodeChunk(
    recognizer: HKGGUFRecognizerHandle, samples: [Float]
  ) -> String? {
    guard !Task.isCancelled, !samples.isEmpty else { return nil }
    llama_memory_clear(llama_get_memory(recognizer.context), true)
    guard let bitmap = samples.withUnsafeBufferPointer({
      mtmd_bitmap_init_from_audio($0.count, $0.baseAddress)
    }) else { return nil }
    defer { mtmd_bitmap_free(bitmap) }
    guard let chunks = mtmd_input_chunks_init() else { return nil }
    defer { mtmd_input_chunks_free(chunks) }
    var bitmaps: [OpaquePointer?] = [bitmap]
    let prompt = "<__media__>"
    let status = prompt.withCString { text in
      var input = mtmd_input_text(
        text: text, text_len: prompt.utf8.count,
        add_special: true, parse_special: true
      )
      return bitmaps.withUnsafeMutableBufferPointer { buffer in
        mtmd_tokenize(recognizer.audio, chunks, &input, buffer.baseAddress, buffer.count)
      }
    }
    guard status == 0, !Task.isCancelled else { return nil }
    var nextPos: llama_pos = 0
    let eval = mtmd_helper_eval_chunks(
      recognizer.audio, recognizer.context, chunks,
      0, 0, 1024, true, &nextPos
    )
    guard eval == 0, !Task.isCancelled else { return nil }

    guard let sampler = llama_sampler_init_greedy() else { return nil }
    defer { llama_sampler_free(sampler) }
    let vocab = llama_model_get_vocab(recognizer.model)
    var batch = llama_batch_init(1, 0, 1)
    defer { llama_batch_free(batch) }
    var output = [UInt8]()
    output.reserveCapacity(768)
    for _ in 0..<256 {
      guard !Task.isCancelled else { return nil }
      let token = llama_sampler_sample(sampler, recognizer.context, -1)
      if llama_vocab_is_eog(vocab, token) { break }
      var bytes = [CChar](repeating: 0, count: 256)
      let count = llama_token_to_piece(vocab, token, &bytes, Int32(bytes.count), 0, true)
      if count > 0 {
        output.append(contentsOf: bytes.prefix(Int(count)).map { UInt8(bitPattern: $0) })
      }
      batch.n_tokens = 1
      batch.token[0] = token
      batch.pos[0] = nextPos
      batch.n_seq_id[0] = 1
      batch.seq_id[0]?[0] = 0
      batch.logits[0] = 1
      nextPos += 1
      guard llama_decode(recognizer.context, batch) == 0 else { return nil }
    }
    var text = String(decoding: output, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    // Qwen3-ASR emits language metadata before the actual transcript.
    if let tag = text.range(of: "<asr_text>") {
      text = String(text[tag.upperBound...])
    } else if text.hasPrefix("language ") {
      return nil
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
