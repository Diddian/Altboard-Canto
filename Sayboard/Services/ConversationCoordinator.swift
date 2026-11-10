import AVFoundation
import Combine
import Foundation
import NaturalLanguage
import os

@MainActor
final class ConversationCoordinator: ObservableObject {
  static let shared = ConversationCoordinator()
  static let maximumTurnSeconds: TimeInterval = 25

  @Published private(set) var turns: [ConversationTurn] = []
  @Published private(set) var recordingSide: ConversationSpeaker?
  @Published private(set) var processing = false
  @Published private(set) var liveSource = ""
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
    guard self.recordingSide == nil, !self.processing,
          !service.isRecording, !service.isStopping,
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
      self.activeID = identifier
      self.captureOptions = options
      self.recordingSide = side
      self.elapsed = 0
      self.liveSource = ""
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
      if service.activeLoadState != .loaded,
         let downloads = service.downloadService {
        let availableMB = Int(os_proc_available_memory() / 1_048_576)
        let minimumMB = max(2_400,
          Int(Double(SharedSettings().selectedVariant.ramRequirementMB) * 0.58))
        if availableMB >= minimumMB {
          self.warmupTask = Task { @MainActor [weak self, weak service] in
            guard let self, let service else { return }
            await service.loadModelIfAvailable(downloadService: downloads)
            if self.recordingSide != nil, service.activeLoadState == .loaded {
              self.startLivePreview(using: service)
            }
          }
        } else {
          self.status = "Recording audio; original words will appear after Stop."
          FeatureDiagnostics.record(.conversation, .fallback)
        }
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
    let samples = self.accumulator.consumeAll()
    self.accumulator.reset()
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
    guard let saved, !saved.writeFailed, saved.duration > 0 else {
      self.status = "Audio could not be saved. Nothing was overwritten."
      self.processing = false
      FeatureDiagnostics.record(.conversation, .failed)
      return
    }
    let requested = self.captureOptions ?? Self.defaultOutput(for: side)
    self.captureOptions = nil
    let code = PreferredVoiceLanguages.currentCode(
      target: requested.target, custom: requested.customLanguage
    )
    let index = self.turns.count
    self.turns.append(ConversationTurn(
      id: identifier, speaker: side,
      audioFileName: saved.url.lastPathComponent, duration: saved.duration,
      targetCode: code, sourceText: "", translatedText: nil,
      detectedLanguageCode: nil, status: "processing"
    ))
    guard self.persistDraft() else {
      self.turns.removeLast()
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
      self.turns[index].status = "speechFailed"
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
      self.turns[index].status = "speechFailed"
      self.status = "Recognition failed. Original audio was retained."
      _ = self.persistDraft()
      FeatureDiagnostics.record(.conversation, .failed)
      return
    }
    let source = CantoneseOutput.normalize(TextSanitizer.sanitize(output.text))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty else {
      self.turns[index].status = "noSpeech"
      self.status = "No speech detected. Audio retained."
      _ = self.persistDraft()
      FeatureDiagnostics.record(.conversation, .noSpeech)
      return
    }
    let identifier = NLLanguageRecognizer()
    identifier.processString(source)
    self.turns[index].sourceText = source
    self.turns[index].detectedLanguageCode = identifier.dominantLanguage?.rawValue
    self.turns[index].status = "transcribed"
    _ = self.persistDraft()
    if options.target == .original {
      self.turns[index].status = "original"
      self.status = "Original transcript saved"
      _ = self.persistDraft()
      return
    }
    self.status = "Translating to " + self.turns[index].targetCode.uppercased() + "…"
    guard let coordinator = service.llmCoordinator,
          coordinator.downloadService?.hasUsableModel == true else {
      self.turns[index].status = "translationFailed"
      self.status = "Text Model missing. Original saved; translate again after download."
      _ = self.persistDraft()
      FeatureDiagnostics.record(.conversation, .unavailable)
      return
    }
    let translation = await coordinator.processVoiceDictation(source, options: options)
    if let translation, !translation.isEmpty {
      self.turns[index].translatedText = translation
      self.turns[index].status = "translated"
      self.status = "Translation ready"
      FeatureDiagnostics.record(.conversation, .completed)
    } else {
      self.turns[index].status = "translationFailed"
      self.status = "Translation failed. Original saved; retry this turn."
      FeatureDiagnostics.record(.conversation, .failed)
    }
    _ = self.persistDraft()
  }

  func retry(_ turnID: UUID, using service: SpeechRecognitionService) async {
    guard !self.processing, self.recordingSide == nil,
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
      let output = await coordinator.processVoiceDictation(turn.sourceText, options: options)
      if let output, !output.isEmpty {
        self.turns[index].translatedText = output
        self.turns[index].status = "translated"
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

  func discardDraft() {
    guard self.recordingSide == nil, !self.processing else { return }
    if let folder = Self.folder { try? FileManager.default.removeItem(at: folder) }
    self.turns = []
    self.status = "Conversation cleared"
    FeatureDiagnostics.record(.conversation, .cancelled)
  }

  private func startLivePreview(using service: SpeechRecognitionService) {
    self.liveTask?.cancel()
    guard service.activeLoadState == .loaded else { return }
    self.liveTask = Task { @MainActor [weak self, weak service] in
      guard let self, let service else { return }
      var offset = 0
      let frameCount = 48_000 // 3 seconds, never a second recorder
      while !Task.isCancelled && self.recordingSide != nil {
        guard let samples = self.accumulator.chunk(from: offset, count: frameCount)
        else {
          do { try await Task.sleep(for: .milliseconds(130)) }
          catch { break }
          continue
        }
        offset += samples.count
        let result = await service.transcribeSamples(samples)
        guard !Task.isCancelled, self.recordingSide != nil else { break }
        if case .text(let output) = result {
          let raw = TextSanitizer.sanitize(output.text)
          if !raw.isEmpty {
            self.liveSource = ExperimentalSpeechSegments.append(raw, to: self.liveSource)
          }
        }
      }
    }
  }

  private static func defaultOutput(for side: ConversationSpeaker) -> VoiceOutputConfiguration {
    .init(cleanupEnabled: false,
          target: side == .other ? .cantonese : .custom,
          register: .faithful, customLanguage: side == .other ? "" : "tr")
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
      cleanupEnabled: false, target: target,
      register: .faithful, customLanguage: target == .custom ? code : ""
    )
  }

  private func persistDraft() -> Bool {
    guard let folder = Self.folder else { return false }
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try JSONEncoder().encode(self.turns).write(
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
    guard let file = Self.folder?.appendingPathComponent("turns.json"),
          let data = try? Data(contentsOf: file),
          let restored = try? JSONDecoder().decode([ConversationTurn].self, from: data)
    else { return }
    self.turns = restored
    self.status = "Unsaved conversation restored. Retry interrupted turns or save as Meeting."
    FeatureDiagnostics.record(.conversation, .fallback)
  }

  /// Read a bounded saved turn for recovery without loading an entire meeting.
  private static func readAudio(at url: URL) -> [Float]? {
    guard ConversationTurnPolicy.validAudioFileName(url.lastPathComponent),
          let file = try? AVAudioFile(forReading: url),
          file.length <= AVAudioFramePosition(25 * file.processingFormat.sampleRate)
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
