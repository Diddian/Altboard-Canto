import AVFoundation
import Combine
import Foundation
import NaturalLanguage
import os

@MainActor
final class ConversationCoordinator: ObservableObject {
  static let shared = ConversationCoordinator()
  static let maximumTurnSeconds = ConversationTurnPolicy.maximumCaptureSeconds

  @Published private(set) var turns: [ConversationTurn] = []
  @Published private(set) var recordingSide: ConversationSpeaker?
  @Published private(set) var processing = false
  @Published private(set) var liveSource = ""
  @Published private(set) var livePreviewUnavailable = false
  @Published private(set) var status = "Ready to talk"
  @Published private(set) var elapsed: TimeInterval = 0

  private let recorder = AudioRecorder()
  private let accumulator = AudioBufferAccumulator(maximumUnreadSamples: 16_000 * 28)
  private var sessionStartedHere = false
  private var captureOptions: VoiceOutputConfiguration?
  private var liveTask: Task<Void, Never>?
  private var warmupTask: Task<Void, Never>?
  private var limitTask: Task<Void, Never>?
  private var sessionObservation: AnyCancellable?
  private var startedAt: Date?
  private var activeID: UUID?
  private var draftStorageReadable = true

  private init() { self.restoreDraft() }

  private static var folder: URL? {
    AppGroup.containerURL?.appendingPathComponent("conversation-draft", isDirectory: true)
  }

  private static var audioFolder: URL? {
    self.folder?.appendingPathComponent("audio", isDirectory: true)
  }

  func start(
    _ side: ConversationSpeaker, using service: SpeechRecognitionService,
    options: VoiceOutputConfiguration
  ) {
    guard ConversationTurnPolicy.validOutput(
      target: options.target, custom: options.customLanguage
    ) else {
      self.status = "Choose a valid output language code before recording."
      return
    }
    guard self.draftStorageReadable, !LocalUserDataStore.isExporting,
          self.recordingSide == nil, !self.processing,
          !service.isRecording, !service.isStopping,
          service.llmCoordinator?.isProcessing != true,
          MeetingRecordingCoordinator.shared.translatingRecordID == nil,
          !MeetingRecordingCoordinator.shared.isRecording,
          !MeetingRecordingCoordinator.shared.isFinalizing,
          service.session.captureOwner == nil,
          SharedSettings().hasUsableModel,
          let folder = Self.audioFolder else {
      self.status = "Microphone or speech model unavailable. Stop other recording first."
      FeatureDiagnostics.record(.conversation, .blocked)
      return
    }
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      self.sessionStartedHere = !service.session.isSessionActive
      if self.sessionStartedHere { try service.session.startSession() }
      let format = service.session.audioEngine.inputNode.outputFormat(forBus: 0)
      let identifier = UUID()
      let name = identifier.uuidString + ".caf"
      self.activeID = identifier
      self.turns.append(ConversationTurn(
        id: identifier, speaker: side, audioFileName: name, duration: 0,
        targetCode: PreferredVoiceLanguages.currentCode(
          target: options.target, custom: options.customLanguage
        ), sourceText: "", translatedText: nil, detectedLanguageCode: nil, status: .recording
      ))
      guard self.persistDraft() else {
        self.turns.removeAll { $0.id == identifier }
        throw ConversationError.storage
      }
      guard self.recorder.startRecording(
        fileName: name, format: format, directory: folder
      ) != nil else {
        throw ConversationError.storage
      }
      self.accumulator.reset()
      do {
        try service.session.beginCapture(
          owner: .conversation, accumulator: self.accumulator, recorder: self.recorder
        )
      } catch {
        if let file = self.recorder.stopRecording() {
          try? FileManager.default.removeItem(at: file.url)
        }
        throw error
      }
      self.captureOptions = options
      self.recordingSide = side
      self.elapsed = 0
      self.liveSource = ""
      self.livePreviewUnavailable = false
      self.startedAt = Date()
      self.status = "Listening · " + side.title
      FeatureDiagnostics.record(.conversation, .started)
      self.sessionObservation = service.session.$isSessionActive.sink { [weak self] active in
        guard !active else { return }
        Task { @MainActor [weak self, weak service] in
          guard let self, let service, self.recordingSide != nil else { return }
          await self.stop(using: service)
        }
      }
      // Partial words are visible while recording when a warmed model is
      // available. Never run two native ASR decodes concurrently.
      self.startLivePreview(using: service)
      if service.activeLoadState != .loaded {
        self.scheduleLivePreviewWarmup(using: service)
      }
      self.limitTask?.cancel()
      self.limitTask = Task { @MainActor [weak self, weak service] in
        guard let self, let service else { return }
        for second in 1...Int(Self.maximumTurnSeconds) {
          do { try await Task.sleep(for: .seconds(1)) }
          catch { return }
          guard !Task.isCancelled, self.recordingSide != nil,
                self.activeID == identifier else { return }
          self.elapsed = TimeInterval(second)
        }
        await self.stop(using: service)
      }
    } catch {
      if let id = self.activeID {
        self.turns.removeAll { $0.id == id }
        _ = self.persistDraft()
      }
      self.activeID = nil
      if self.sessionStartedHere { service.session.endSession() }
      self.status = "Unable to start recording. Check microphone and storage."
      FeatureDiagnostics.record(.conversation, .failed)
    }
  }

  /// Stop capture before awaiting slow native inference. Each completed audio
  /// part is written to the existing App Group before any model processing.
  func stop(using service: SpeechRecognitionService) async {
    guard let side = self.recordingSide, !self.processing,
          let identifier = self.activeID else { return }
    self.processing = true
    self.recordingSide = nil
    self.limitTask?.cancel()
    self.limitTask = nil
    self.sessionObservation?.cancel()
    self.sessionObservation = nil
    service.session.endCapture(owner: .conversation)
    let saved = self.recorder.stopRecording()
    if let saved, let index = self.turns.firstIndex(where: { $0.id == identifier }) {
      self.turns[index].duration = saved.duration
      self.turns[index].status = .processing
      _ = self.persistDraft()
    }
    let samples = self.accumulator.consumeAll()
    self.accumulator.reset()
    if self.liveTask != nil {
      FeatureDiagnostics.record(.liveDictation, .stopped, operationID: identifier.uuidString)
    }
    self.liveTask?.cancel()
    await self.liveTask?.value
    self.liveTask = nil
    await self.warmupTask?.value
    self.warmupTask = nil
    if self.sessionStartedHere { service.session.endSession() }
    self.sessionStartedHere = false
    self.startedAt = nil
    self.activeID = nil
    self.liveSource = ""
    self.livePreviewUnavailable = false
    guard let saved, !saved.writeFailed, saved.duration > 0 else {
      self.status = "Audio could not be saved. Nothing was overwritten."
      self.processing = false
      FeatureDiagnostics.record(.conversation, .failed)
      return
    }
    let requested = self.captureOptions ?? Self.defaultOutput(for: side)
    self.captureOptions = nil
    guard let index = self.turns.firstIndex(where: { $0.id == identifier }) else {
      self.processing = false
      return
    }
    self.turns[index].duration = saved.duration
    self.turns[index].status = .processing
    guard self.persistDraft() else {
      self.status = "Could not save the turn. Audio file retained."
      self.processing = false
      FeatureDiagnostics.record(.conversation, .failed)
      return
    }
    FeatureDiagnostics.record(.conversation, .stopped,
      audioDurationMs: Int(saved.duration * 1_000))
    await self.completeTurn(at: index, samples: samples, using: service, options: requested)
  }

  private func completeTurn(
    at index: Int, samples: [Float], using service: SpeechRecognitionService,
    options: VoiceOutputConfiguration
  ) async {
    defer { self.processing = false }
    guard self.turns.indices.contains(index) else { return }
    self.status = "Recognizing original speech…"
    if service.activeLoadState != .loaded, let downloads = service.downloadService {
      await service.loadModelIfAvailable(downloadService: downloads)
    }
    guard service.activeLoadState == .loaded else {
      self.turns[index].status = .speechFailed
      self.status = "Speech model unavailable. Audio saved; retry this turn."
      _ = self.persistDraft()
      FeatureDiagnostics.record(.conversation, .unavailable)
      return
    }
    let started = CFAbsoluteTimeGetCurrent()
    let result = await service.transcribeSamples(samples)
    FeatureDiagnostics.record(
      .conversation, .completed,
      durationMs: Int((CFAbsoluteTimeGetCurrent() - started) * 1_000),
      audioDurationMs: samples.count / 16, residentMB: ProcessFootprint.residentMB()
    )
    guard case .text(let output) = result else {
      self.turns[index].status = .speechFailed
      self.status = "Recognition failed. Original audio was retained."
      _ = self.persistDraft()
      FeatureDiagnostics.record(.conversation, .failed)
      return
    }
    let source = TextSanitizer.sanitize(output.text)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty else {
      self.turns[index].status = .noSpeech
      self.status = "No speech detected. Audio retained."
      _ = self.persistDraft()
      FeatureDiagnostics.record(.conversation, .noSpeech)
      return
    }
    let identifier = NLLanguageRecognizer()
    identifier.processString(source)
    self.turns[index].sourceText = source
    self.turns[index].detectedLanguageCode = identifier.dominantLanguage?.rawValue
    self.turns[index].status = .transcribed
    _ = self.persistDraft()
    let coordinator = service.llmCoordinator
    let hasTextModel = coordinator?.downloadService?.hasUsableModel == true
    guard hasTextModel, let coordinator else {
      if options.target == .original {
        // Same-language output must remain usable without a text model.
        self.turns[index].status = .original
        self.status = "Transcript saved in original language"
        _ = self.persistDraft()
        FeatureDiagnostics.record(.conversation, .fallback)
        return
      }
      self.turns[index].status = .translationFailed
      self.status = "Text Model missing. Original saved; translate again after download."
      _ = self.persistDraft()
      FeatureDiagnostics.record(.conversation, .unavailable)
      return
    }

    self.status = "Preparing transcript and translation…"
    let turnID = self.turns[index].id
    // Cleanup and translation run in one already-loaded text-model session.
    // Save the cleaned speaker text before the listener's translation finishes.
    let translation = await coordinator.processConversationTurn(source, options: options) {
      [weak self] cleaned in
      guard let self, self.turns.indices.contains(index),
            self.turns[index].id == turnID else { return }
      // A single-pass translation does not independently produce a cleaned
      // source transcript; keep the original rather than mislabeling it.
      self.turns[index].cleanedSourceText = cleaned == source ? nil : cleaned
      self.status = options.target == .original
        ? "Transcript ready" : "Translating…"
      _ = self.persistDraft()
    }

    if options.target == .original {
      self.turns[index].status = .original
      self.status = "Transcript saved in original language"
      _ = self.persistDraft()
      return
    }
    if let translation, !translation.isEmpty {
      self.turns[index].translatedText = translation
      self.turns[index].status = .translated
      self.status = "Translation ready"
      FeatureDiagnostics.record(.conversation, .completed)
    } else {
      self.turns[index].status = .translationFailed
      self.status = "Translation failed. Original saved; retry this turn."
      FeatureDiagnostics.record(.conversation, .failed)
    }
    _ = self.persistDraft()
  }

  func retry(_ turnID: UUID, using service: SpeechRecognitionService) async {
    guard !LocalUserDataStore.isExporting,
          !service.isRecording, !service.isStopping,
          !MeetingRecordingCoordinator.shared.isRecording,
          !MeetingRecordingCoordinator.shared.isFinalizing,
          MeetingRecordingCoordinator.shared.translatingRecordID == nil,
          service.llmCoordinator?.isProcessing != true,
          !self.processing, self.recordingSide == nil,
          let index = self.turns.firstIndex(where: { $0.id == turnID })
    else { return }
    let turn = self.turns[index]
    let options = Self.output(for: turn.targetCode)
    if !turn.sourceText.isEmpty {
      self.processing = true
      defer { self.processing = false }
      guard let coordinator = service.llmCoordinator,
            coordinator.downloadService?.hasUsableModel == true else {
        self.status = "Select a downloaded Text Model to translate."
        return
      }
      self.status = "Retrying translation…"
      let output = await coordinator.processVoiceDictation(
        turn.cleanedSourceText ?? turn.sourceText, options: options
      )
      if let output, !output.isEmpty {
        self.turns[index].translatedText = output
        self.turns[index].status = .translated
        self.status = "Translation ready"
      } else {
        self.status = "Translation still unavailable. Original saved."
      }
      _ = self.persistDraft()
      return
    }
    guard let audio = Self.audioFolder?.appendingPathComponent(turn.audioFileName),
          let samples = Self.readAudio(at: audio), !samples.isEmpty else {
      self.status = "Saved audio could not be read."
      return
    }
    self.processing = true
    await self.completeTurn(at: index, samples: samples, using: service, options: options)
  }

  func saveAsMeeting() -> Bool {
    guard !self.processing, self.recordingSide == nil,
          !self.turns.isEmpty, let folder = Self.folder else { return false }
    guard MeetingRecordingCoordinator.shared.saveConversation(
      turns: self.turns, audioDirectory: folder.appendingPathComponent("audio")
    ) else {
      self.status = "Could not save as Meeting. Conversation draft retained."
      FeatureDiagnostics.record(.conversation, .failed)
      return false
    }
    self.turns = []
    try? FileManager.default.removeItem(at: folder)
    self.status = "Saved in Meetings"
    FeatureDiagnostics.record(.conversation, .completed)
    return true
  }

  @discardableResult
  func discardDraft() -> Bool {
    guard self.recordingSide == nil, !self.processing else { return false }
    if let folder = Self.folder, FileManager.default.fileExists(atPath: folder.path) {
      do { try FileManager.default.removeItem(at: folder) }
      catch {
        self.status = "Could not clear the conversation. Saved draft retained."
        FeatureDiagnostics.record(.conversation, .failed)
        return false
      }
    }
    self.turns = []
    self.draftStorageReadable = true
    self.status = "Conversation cleared"
    FeatureDiagnostics.record(.conversation, .cancelled)
    return true
  }

  /// Prepare the selected offline recognizer when Conversation becomes visible.
  /// Reuse the same task after recording begins; do not start a second load.
  func prepareLivePreview(using service: SpeechRecognitionService) {
    guard self.recordingSide == nil, !self.processing,
          !LocalUserDataStore.isExporting,
          !service.isModelInUse, !service.isStopping,
          service.llmCoordinator?.isProcessing != true,
          MeetingRecordingCoordinator.shared.translatingRecordID == nil,
          !MeetingRecordingCoordinator.shared.isFinalizing else { return }
    self.scheduleLivePreviewWarmup(using: service)
  }

  private func scheduleLivePreviewWarmup(using service: SpeechRecognitionService) {
    guard self.warmupTask == nil, service.activeLoadState == .unloaded else { return }
    guard let downloads = service.downloadService else {
      if self.recordingSide != nil {
        self.livePreviewUnavailable = true
        self.status = "Live text unavailable; downloaded speech model not found."
        FeatureDiagnostics.record(.liveDictation, .fallback, failureReason: .missingModelFile)
      }
      return
    }
    let availableMB = Int(os_proc_available_memory() / 1_048_576)
    let minimumMB = max(2_400,
      Int(Double(SharedSettings().selectedVariant.ramRequirementMB) * 0.58))
    guard availableMB >= minimumMB else {
      if self.recordingSide != nil {
        self.livePreviewUnavailable = true
        self.status = "Live text unavailable due to memory pressure; transcript after Stop."
        FeatureDiagnostics.record(.liveDictation, .fallback, failureReason: .insufficientMemory)
      }
      return
    }
    self.warmupTask = Task { @MainActor [weak self, weak service] in
      guard let self, let service else { return }
      await service.loadModelIfAvailable(downloadService: downloads)
      if service.activeLoadState == .loaded {
        if self.recordingSide != nil { self.startLivePreview(using: service) }
      } else if self.recordingSide != nil {
        self.livePreviewUnavailable = true
        self.status = "Live text unavailable; recording is saved for transcription after Stop."
        FeatureDiagnostics.record(.liveDictation, .fallback, failureReason: .modelLoadFailed)
      }
      self.warmupTask = nil
    }
  }

  private func startLivePreview(using service: SpeechRecognitionService) {
    guard self.liveTask == nil, service.activeLoadState == .loaded else { return }
    self.livePreviewUnavailable = false
    let operationID = self.activeID?.uuidString
    FeatureDiagnostics.record(.liveDictation, .started, operationID: operationID)
    self.liveTask = Task { @MainActor [weak self, weak service] in
      guard let self, let service else { return }
      var offset = 0
      let previewStarted = CFAbsoluteTimeGetCurrent()
      var didPublishFirstUpdate = false
      var hasAttemptedFirst = false
      while !Task.isCancelled && self.recordingSide != nil {
        let frameCount = LiveDictationChunkPolicy.samples(
          isQwen: service.settings.selectedVariant.engine == .qwen3,
          hasAttemptedFirst: hasAttemptedFirst
        )
        guard let samples = self.accumulator.chunk(from: offset, count: frameCount)
        else {
          do { try await Task.sleep(for: .milliseconds(130)) }
          catch { break }
          continue
        }
        offset += samples.count
        let firstChunk = !hasAttemptedFirst
        hasAttemptedFirst = true
        let result = await service.transcribeSamples(samples)
        guard !Task.isCancelled, self.recordingSide != nil else { break }
        switch result {
        case .text(let output):
          let raw = TextSanitizer.sanitize(output.text)
          if !raw.isEmpty {
            self.liveSource = ExperimentalSpeechSegments.append(raw, to: self.liveSource)
            if !didPublishFirstUpdate {
              didPublishFirstUpdate = true
              FeatureDiagnostics.record(.liveDictation, .firstUpdate,
                durationMs: Int((CFAbsoluteTimeGetCurrent() - previewStarted) * 1_000),
                operationID: operationID)
            }
          } else if firstChunk {
            FeatureDiagnostics.record(.liveDictation, .noSpeech, operationID: operationID)
          }
        case .noSpeech:
          if firstChunk { FeatureDiagnostics.record(.liveDictation, .noSpeech, operationID: operationID) }
        case .failed:
          if firstChunk { FeatureDiagnostics.record(.liveDictation, .failed, operationID: operationID) }
        }
      }
    }
  }

  private static func defaultOutput(for side: ConversationSpeaker) -> VoiceOutputConfiguration {
    .init(cleanupEnabled: true,
          target: side == .other ? .cantonese : .german,
          register: .faithful, customLanguage: "")
  }

  private static func output(for code: String) -> VoiceOutputConfiguration {
    let target: VoiceOutputTarget =
      switch code {
      case "yue": .cantonese
      case "zh": .traditionalChinese
      case "en": .english
      case "de": .german
      case "": .original
      default: .custom
      }
    return .init(
      cleanupEnabled: true, target: target,
      register: .faithful, customLanguage: target == .custom ? code : ""
    )
  }

  private func persistDraft() -> Bool {
    guard let folder = Self.folder else { return false }
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try JSONEncoder().encode(ConversationDraft(schemaVersion: 1, turns: self.turns)).write(
        to: folder.appendingPathComponent("turns.json"),
        options: [.atomic, .completeFileProtectionUnlessOpen]
      )
      return true
    } catch {
      FeatureDiagnostics.record(.conversation, .failed)
      return false
    }
  }

  private func restoreDraft() {
    guard let folder = Self.folder else { return }
    let data = try? Data(contentsOf: folder.appendingPathComponent("turns.json"))
    if let data {
      if let draft = try? JSONDecoder().decode(ConversationDraft.self, from: data),
         draft.schemaVersion == 1 {
        self.turns = draft.turns
      } else if let old = try? JSONDecoder().decode([ConversationTurn].self, from: data) {
        self.turns = old
      } else {
        self.draftStorageReadable = false
        self.status = "Saved conversation could not be read. Original files retained."
        FeatureDiagnostics.record(.conversation, .failed)
        return
      }
    }
    for index in self.turns.indices where self.turns[index].status == .recording
        || self.turns[index].status == .processing {
      self.turns[index].status = .interrupted
    }
    let audio = folder.appendingPathComponent("audio", isDirectory: true)
    let files = (try? FileManager.default.contentsOfDirectory(at: audio,
      includingPropertiesForKeys: nil)) ?? []
    for file in files where ConversationTurnPolicy.validAudioFileName(file.lastPathComponent) {
      guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
            let recording = try? AVAudioFile(forReading: file),
            recording.processingFormat.sampleRate > 0 else { continue }
      let duration = Double(recording.length) / recording.processingFormat.sampleRate
      if let index = self.turns.firstIndex(where: { $0.id == id }) {
        if self.turns[index].duration == 0 { self.turns[index].duration = duration }
      } else {
        self.turns.append(ConversationTurn(
          id: id, speaker: .me, audioFileName: file.lastPathComponent, duration: duration,
          targetCode: "", sourceText: "", translatedText: nil,
          detectedLanguageCode: nil, status: .interrupted
        ))
      }
    }
    guard !self.turns.isEmpty else { return }
    _ = self.persistDraft()
    self.status = "Previous conversation restored. Retry unfinished turns or save as a Meeting."
    FeatureDiagnostics.record(.conversation, .fallback)
  }

  /// Read a bounded saved turn for recovery without loading an entire meeting.
  private static func readAudio(at url: URL) -> [Float]? {
    guard ConversationTurnPolicy.validAudioFileName(url.lastPathComponent),
          let file = try? AVAudioFile(forReading: url),
          file.length <= AVAudioFramePosition(ConversationTurnPolicy.maximumRecoverySeconds * file.processingFormat.sampleRate)
    else { return nil }
    let format = file.processingFormat
    let destination = AVAudioFormat(
      commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
      channels: 1, interleaved: false
    )
    guard let destination else { return nil }
    let converter = format.sampleRate == 16_000 && format.channelCount == 1
      ? nil : AVAudioConverter(from: format, to: destination)
    if (format.sampleRate != 16_000 || format.channelCount != 1) && converter == nil {
      return nil
    }
    let diagnostics = OSAllocatedUnfairLock(initialState: TapDiagnostics())
    var samples: [Float] = []
    while file.framePosition < file.length {
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)
      else { return nil }
      do { try file.read(into: buffer) } catch { return nil }
      guard buffer.frameLength > 0 else { break }
      let chunk = converter.map {
        AudioBufferMath.resample(buffer, converter: $0, targetFormat: destination,
                                 diagnostics: diagnostics)
      } ?? AudioBufferMath.samples(from: buffer)
      samples.append(contentsOf: chunk)
      guard samples.count <= 16_000 * 26 else { return nil }
    }
    return samples
  }

  enum ConversationError: Error {
    case storage
  }
}

