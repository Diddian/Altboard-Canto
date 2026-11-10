import AVFoundation
import Combine
import Foundation

struct MeetingAudioPart: Codable, Identifiable {
  let number: Int
  let fileName: String
  let startOffset: TimeInterval
  let duration: TimeInterval
  var id: Int { number }
}

struct MeetingRecord: Codable, Identifiable {
  let id: UUID
  let startedAt: Date
  var endedAt: Date?
  var parts: [MeetingAudioPart]
  var transcript: String
  var state: String
  // Optional metadata preserves decoding of recordings made before naming.
  var title: String?
  var notes: String?
  var sequenceNumber: Int? = nil
  // Optional fields keep older manifests decodable. Original ASR is immutable;
  // translation is separate and an interrupted attempt can resume safely.
  var translatedTranscript: String? = nil
  var translatedLanguageCode: String? = nil
  var translationDraftText: String? = nil
  var translationDraftConfiguration: String? = nil
  var translationDraftFingerprint: String? = nil
  var translationDraftNextChunk: Int? = nil

  var totalDuration: TimeInterval {
    self.parts.reduce(0) { $0 + $1.duration }
  }

  var displayTitle: String {
    let value = (self.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? "New Meeting \(self.sequenceNumber ?? 1)" : value
  }
}

/// Opt-in experiment. No cloud uploads and no second microphone tap.
@MainActor
final class MeetingRecordingCoordinator: ObservableObject {
  static let shared = MeetingRecordingCoordinator()
  static let partDuration: TimeInterval = 15 * 60
  static let updateSeconds = 8
  private static let meetingSequenceKey = "canto.meeting.lastSequenceNumber.v1"

  @Published private(set) var isRecording = false
  @Published private(set) var isFinalizing = false
  @Published private(set) var elapsed: TimeInterval = 0
  @Published private(set) var status = "Not recording"
  @Published private(set) var current: MeetingRecord?
  @Published private(set) var records = [MeetingRecord]()
  @Published private(set) var unreadableRecordCount = 0
  @Published private(set) var translatingRecordID: UUID?
  @Published private(set) var translationStatus = ""
  private var translationTask: Task<Void, Never>?

  private let audioRecorder = AudioRecorder()
  private let accumulator = AudioBufferAccumulator(maximumUnreadSamples: 16_000 * 120)
  private weak var speechService: SpeechRecognitionService?
  private var currentFormat: AVAudioFormat?
  private var currentAudioDirectory: URL?
  private var lastPartStartedAt = Date()
  private var timer: Timer?
  private var decodeTask: Task<Void, Never>?
  private var sessionObservation: AnyCancellable?
  private var incompleteTranscript = false
  private var incompleteAudio = false
  private var backlogOverflowReported = false

  private init() { self.reloadRecords() }

  func start(with service: SpeechRecognitionService, title: String = "", notes: String = "") {
    guard !self.isRecording, !self.isFinalizing, self.translatingRecordID == nil,
          !service.isRecording, !service.isStopping,
          SharedSettings().hasUsableModel,
          let root = Self.meetingsDirectory() else {
      FeatureDiagnostics.record(.meeting, .blocked)
      self.status = "Download and select a speech model. Stop other dictation first."
      return
    }
    let sessionStartedHere = !service.session.isSessionActive
    do { try service.session.startSession() }
    catch {
      FeatureDiagnostics.record(.meeting, .failed)
      self.status = "Unable to activate microphone"
      return
    }
    let id = UUID()
    let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
    let audioDirectory = folder.appendingPathComponent("audio", isDirectory: true)
    do { try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true) }
    catch {
      FeatureDiagnostics.record(.meeting, .failed)
      self.status = "Cannot create meeting storage"
      self.abortStart(service: service, sessionStartedHere: sessionStartedHere, folder: folder)
      return
    }
    let format = service.session.audioEngine.inputNode.outputFormat(forBus: 0)
    guard self.audioRecorder.startRecording(fileName: "0001.caf", format: format,
                                            directory: audioDirectory) != nil else {
      FeatureDiagnostics.record(.meeting, .failed)
      self.status = "Cannot open meeting audio file"
      self.abortStart(service: service, sessionStartedHere: sessionStartedHere, folder: folder)
      return
    }
    self.speechService = service
    self.currentFormat = format
    self.currentAudioDirectory = audioDirectory
    let defaults = SharedSettings().defaults
    let nextNumber = max(
      defaults.integer(forKey: Self.meetingSequenceKey),
      self.records.compactMap(\.sequenceNumber).max() ?? self.records.count
    ) + 1
    self.current = MeetingRecord(
      id: id, startedAt: Date(), endedAt: nil, parts: [],
      transcript: "", state: "recording",
      title: Self.normalized(title, limit: 120),
      notes: Self.normalized(notes, limit: 4000),
      sequenceNumber: nextNumber
    )
    self.lastPartStartedAt = Date()
    self.accumulator.reset()
    self.incompleteTranscript = false
    self.incompleteAudio = false
    self.backlogOverflowReported = false
    do {
      try service.session.beginCapture(owner: .meeting, accumulator: self.accumulator, recorder: self.audioRecorder)
    } catch {
      FeatureDiagnostics.record(.meeting, .failed)
      self.status = "Microphone audio unavailable; reconnect it and try again."
      self.abortStart(service: service, sessionStartedHere: sessionStartedHere, folder: folder)
      return
    }
    defaults.set(nextNumber, forKey: Self.meetingSequenceKey)
    self.elapsed = 0
    self.isRecording = true
    FeatureDiagnostics.record(.meeting, .started)
    self.status = "Recording on iPhone"
    self.saveManifest()
    self.sessionObservation = service.session.$isSessionActive.sink { [weak self] active in
      guard !active else { return }
      Task { @MainActor [weak self] in self?.stop(interrupted: true) }
    }
    self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.heartbeat() }
    }
    self.decodeTask = Task { @MainActor [weak self, weak service] in
      guard let self, let service else { return }
      if service.activeLoadState != .loaded, let downloads = service.downloadService {
        await service.loadModelIfAvailable(downloadService: downloads)
      }
      while !Task.isCancelled && self.isRecording {
        guard service.activeLoadState == .loaded,
              let samples = self.accumulator.consume(count: Self.updateSeconds * 16_000)
        else {
          try? await Task.sleep(for: .milliseconds(400))
          continue
        }
        let result = await service.transcribeSamples(samples)
        // The current decoded chunk is still part of the saved meeting even
        // when Stop was pressed during the native inference call.
        switch result {
        case .text(let output):
          self.appendTranscript(output.text)
        case .failed:
          self.incompleteTranscript = true
          FeatureDiagnostics.record(.meeting, .fallback)
        case .noSpeech:
          break
        }
      }
    }
  }

  private func abortStart(
    service: SpeechRecognitionService,
    sessionStartedHere: Bool,
    folder: URL? = nil
  ) {
    if let recording = self.audioRecorder.stopRecording() {
      try? FileManager.default.removeItem(at: recording.url)
    }
    if let folder { try? FileManager.default.removeItem(at: folder) }
    self.accumulator.reset()
    self.current = nil
    self.currentFormat = nil
    self.currentAudioDirectory = nil
    self.speechService = nil
    if sessionStartedHere { service.session.endSession() }
  }

  func stop(interrupted: Bool = false) {
    guard self.isRecording else { return }
    self.isRecording = false
    self.timer?.invalidate()
    self.timer = nil
    let finishingDecode = self.decodeTask
    finishingDecode?.cancel()
    self.decodeTask = nil
    self.speechService?.session.endCapture(owner: .meeting)
    self.closeCurrentPart()
    self.speechService?.session.endSession()
    self.sessionObservation?.cancel()
    self.sessionObservation = nil
    self.isFinalizing = true
    FeatureDiagnostics.record(.meeting, interrupted ? .interrupted : .stopped)
    self.status = "Saving final transcript…"
    let service = self.speechService
    Task { @MainActor [weak self] in
      guard let self else { return }
      // Never race a second native decode against an in-flight ASR call.
      await finishingDecode?.value
      var transcriptIncomplete = self.incompleteTranscript
      if self.accumulator.droppedSampleCount > 0 {
        transcriptIncomplete = true
      }
      if let service, service.activeLoadState == .loaded {
        // Process a bounded slice at a time, even if recognition fell far behind.
        while self.accumulator.sampleCount > 0 {
          let available = self.accumulator.sampleCount
          let count = min(Self.updateSeconds * 16_000, available)
          guard let samples = self.accumulator.consume(count: count) else {
            transcriptIncomplete = true
            break
          }
          let result = await service.transcribeSamples(samples)
          switch result {
          case .text(let output): self.appendTranscript(output.text)
          case .failed: transcriptIncomplete = true
          case .noSpeech: break
          }
        }
      } else if self.accumulator.sampleCount > 0 {
        transcriptIncomplete = true
      }
      // All audio has been written to the meeting files; release queued RAM.
      self.accumulator.reset()
      var manifestSaved = false
      if var record = self.current {
        record.endedAt = Date()
        record.state = self.incompleteAudio ? "partialAudio"
          : (interrupted ? "interrupted"
            : (transcriptIncomplete ? "partialTranscript" : "completed"))
        self.current = record
        manifestSaved = self.writeManifest(record)
      }
      FeatureDiagnostics.record(
        .meeting, !manifestSaved ? .failed
          : ((transcriptIncomplete || self.incompleteAudio) ? .fallback : .completed)
      )
      self.status = !manifestSaved ? "Could not save meeting details; audio files retained"
        : (self.incompleteAudio ? "Audio incomplete; saved parts retained"
        : (interrupted ? "Recording interrupted; saved available audio"
          : (transcriptIncomplete ? "Meeting saved; transcript incomplete, audio retained" : "Meeting saved")))
      self.speechService = nil
      self.currentFormat = nil
      self.currentAudioDirectory = nil
      self.isFinalizing = false
      self.reloadRecords()
      // Meeting output-language selection is honored after saving raw ASR.
      // Start only when a text model is available; otherwise the transcript
      // remains available for an explicit translation from meeting details.
      if !interrupted, manifestSaved, !transcriptIncomplete,
         let service, let saved = self.current,
         !saved.transcript.isEmpty,
         SharedSettings().voiceOutputTarget != .original,
         service.llmCoordinator?.downloadService?.hasUsableModel == true {
        self.translateRecord(id: saved.id, using: service)
      }
    }
  }

  private func heartbeat() {
    guard self.isRecording, let start = self.current?.startedAt else { return }
    self.elapsed = Date().timeIntervalSince(start)
    if self.audioRecorder.hasWriteFailure {
      self.status = "Audio storage failed; preserving available recording"
      self.stop(interrupted: true)
      return
    }
    if !self.backlogOverflowReported && self.accumulator.droppedSampleCount > 0 {
      self.backlogOverflowReported = true
      self.incompleteTranscript = true
      FeatureDiagnostics.record(.meeting, .fallback)
      self.status = "Transcription is behind; full audio is still saved"
    }
    if Date().timeIntervalSince(self.lastPartStartedAt) >= Self.partDuration {
      guard let directory = self.currentAudioDirectory,
            let format = self.currentFormat,
            let count = self.current?.parts.count else {
        self.stop(interrupted: true)
        return
      }
      do {
        let saved = try self.audioRecorder.rotateRecording(
          fileName: String(format: "%04d.caf", count + 2), format: format, directory: directory
        )
        self.retainPart(saved)
        self.lastPartStartedAt = Date()
        FeatureDiagnostics.record(.meeting, .rotated)
      } catch {
        self.incompleteAudio = true
        FeatureDiagnostics.record(.meeting, .failed)
        self.status = "Audio file rotation failed"
        self.stop(interrupted: true)
        return
      }
      self.status = "Recording on iPhone — new 15-minute part"
    }
  }

  private func closeCurrentPart() {
    self.retainPart(self.audioRecorder.stopRecording())
  }

  private func retainPart(_ saved: AudioRecorder.RecordingResult?) {
    guard let saved,
          var record = self.current else { return }
    if saved.writeFailed {
      self.incompleteAudio = true
      FeatureDiagnostics.record(.meeting, .failed)
    }
    // Exact-boundary Stop must not create a ninth empty part.
    guard saved.duration >= 0.15 else {
      try? FileManager.default.removeItem(at: saved.url)
      return
    }
    let number = record.parts.count + 1
    let offset = record.parts.reduce(0.0) { $0 + $1.duration }
    record.parts.append(MeetingAudioPart(number: number, fileName: saved.url.lastPathComponent,
                                         startOffset: offset, duration: saved.duration))
    self.current = record
    self.saveManifest()
  }

  private func appendTranscript(_ raw: String) {
    guard var record = self.current else { return }
    let clean = CantoneseOutput.normalize(TextSanitizer.sanitize(raw))
    guard !clean.isEmpty else { return }
    record.transcript = ExperimentalSpeechSegments.append(clean, to: record.transcript)
    self.current = record
    self.saveManifest()
  }

  private static func normalized(_ value: String, limit: Int) -> String {
    String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
  }

  /// Opt-in post-recording translation. Changing the keyboard output language
  /// cannot retroactively alter a stored ASR record. Translation only starts
  /// here, keeps the original transcript, and saves each confirmed chunk.
  func translateRecord(id: UUID, using service: SpeechRecognitionService) {
    guard self.translatingRecordID == nil, !self.isRecording, !self.isFinalizing,
          let index = self.records.firstIndex(where: { $0.id == id }) else { return }
    let settings = SharedSettings()
    settings.synchronize()
    let options = settings.voiceOutputConfiguration
    guard options.target != .original else {
      self.translationStatus = "Choose an output language in Settings first."
      return
    }
    guard let coordinator = service.llmCoordinator,
          coordinator.downloadService?.hasUsableModel == true else {
      self.translationStatus = "Download and select a Text Model in Settings to translate offline."
      FeatureDiagnostics.record(.meetingTranslation, .unavailable)
      return
    }
    let chunks = MeetingTranslationPolicy.chunks(self.records[index].transcript)
    guard !chunks.isEmpty else {
      self.translationStatus = "The meeting has no transcript to translate."
      return
    }
    let fingerprint = MeetingTranslationPolicy.sourceFingerprint(
      self.records[index].transcript
    )
    let configuration = [
      options.target.rawValue, options.customLanguage, options.register.rawValue,
      options.cleanupEnabled ? "clean" : "raw",
      options.punctuationEnabled ? "punct" : "plain"
    ].joined(separator: "|")
    let language = PreferredVoiceLanguages.currentCode(
      target: options.target, custom: options.customLanguage
    )
    var draft = self.records[index]
    let resume = MeetingTranslationPolicy.canResume(
      sourceFingerprint: fingerprint, configurationKey: configuration,
      savedFingerprint: draft.translationDraftFingerprint,
      savedConfigurationKey: draft.translationDraftConfiguration,
      processedChunks: draft.translationDraftNextChunk,
      totalChunks: chunks.count, savedTranslation: draft.translationDraftText
    )
    if !resume {
      draft.translationDraftText = nil
      draft.translationDraftNextChunk = 0
      draft.translationDraftFingerprint = fingerprint
      draft.translationDraftConfiguration = configuration
      // Keep the previous successfully translated result until replacement
      // fully completes; never discard source or previous valid translation.
    }
    let initial = draft.translationDraftNextChunk ?? 0
    guard self.writeManifest(draft, includeTranscript: false) else {
      self.translationStatus = "Could not save translation progress. Original text is safe."
      return
    }
    self.records[index] = draft
    self.translatingRecordID = id
    self.translationStatus = "Translating \(initial) of \(chunks.count) sections…"
    self.translationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let completed: Bool
      if initial == chunks.count {
        completed = true
      } else {
        completed = await coordinator.translateMeetingChunks(
          chunks, startingAt: initial, options: options
        ) { next, translated in
          guard !Task.isCancelled, self.translatingRecordID == id,
                let position = self.records.firstIndex(where: { $0.id == id })
          else { return false }
          var updated = self.records[position]
          updated.translationDraftText = MeetingTranslationPolicy.combined(
            updated.translationDraftText, next: translated
          )
          updated.translationDraftNextChunk = next
          guard self.writeManifest(updated, includeTranscript: false) else {
            self.translationStatus = "Could not save translation progress. Original text is safe."
            return false
          }
          self.records[position] = updated
          self.translationStatus = "Translated \(next) of \(chunks.count) sections…"
          return true
        }
      }
      if completed, !Task.isCancelled,
         let position = self.records.firstIndex(where: { $0.id == id }) {
        var finished = self.records[position]
        finished.translatedTranscript = finished.translationDraftText
        finished.translatedLanguageCode = language
        finished.translationDraftText = nil
        finished.translationDraftFingerprint = nil
        finished.translationDraftConfiguration = nil
        finished.translationDraftNextChunk = nil
        if self.writeManifest(finished, includeTranscript: false) {
          self.records[position] = finished
          self.translationStatus = "Translation saved. Original ASR retained."
        } else {
          self.translationStatus = "Translation could not be saved. Resume to retry."
        }
      } else if Task.isCancelled {
        self.translationStatus = "Translation paused. Saved sections can be resumed."
      } else if !self.translationStatus.hasPrefix("Could not save") {
        self.translationStatus = "Translation stopped. Saved sections can be resumed."
      }
      self.translatingRecordID = nil
      self.translationTask = nil
    }
  }

  func cancelTranslation(id: UUID) {
    guard self.translatingRecordID == id else { return }
    self.translationStatus = "Pausing translation; saved sections are retained…"
    self.translationTask?.cancel()
  }

  /// Update metadata only. Audio files, transcript and recording timestamps
  /// are not renamed or moved, so existing exported files remain valid.
  @discardableResult
  func updateRecord(id: UUID, title: String, notes: String) -> Bool {
    guard var record = (self.current?.id == id ? self.current : nil)
      ?? self.records.first(where: { $0.id == id }) else { return false }
    record.title = Self.normalized(title, limit: 120)
    record.notes = Self.normalized(notes, limit: 4000)
    guard self.writeManifest(record) else { return false }
    if self.current?.id == id { self.current = record }
    if let index = self.records.firstIndex(where: { $0.id == id }) {
      self.records[index] = record
    }
    return true
  }

  private func saveManifest() {
    guard let record = self.current else { return }
    _ = self.writeManifest(record)
  }

  @discardableResult
  private func writeManifest(
    _ record: MeetingRecord, includeTranscript: Bool = true
  ) -> Bool {
    guard let root = Self.meetingsDirectory(),
          let data = try? JSONEncoder().encode(record) else {
      FeatureDiagnostics.record(.meeting, .failed)
      return false
    }
    let folder = root.appendingPathComponent(record.id.uuidString, isDirectory: true)
    let manifest = folder.appendingPathComponent("manifest.json")
    do {
      try data.write(to: manifest, options: [.atomic, .completeFileProtectionUnlessOpen])
      if includeTranscript {
        let transcriptURL = folder.appendingPathComponent("transcript.txt")
        try record.transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
          [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: transcriptURL.path
        )
      }
      return true
    } catch {
      FeatureDiagnostics.record(.meeting, .failed)
      self.status = "Could not save meeting details"
      return false
    }
  }

  func reloadRecords() {
    guard let root = Self.meetingsDirectory(),
          let folders = try? FileManager.default.contentsOfDirectory(at: root,
                                              includingPropertiesForKeys: nil) else { return }
    var unreadable = 0
    let loaded = folders.compactMap { folder -> MeetingRecord? in
      // Preserve unrecognized meeting folders instead of silently hiding
      // their saved audio after interrupted writes or process termination.
      guard let folderID = UUID(uuidString: folder.lastPathComponent) else { return nil }
      guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
            let record = try? JSONDecoder().decode(MeetingRecord.self, from: data),
            record.id == folderID else {
        unreadable += 1
        return nil
      }
      return record
    }.sorted { $0.startedAt < $1.startedAt }
    if unreadable != self.unreadableRecordCount {
      self.unreadableRecordCount = unreadable
      if unreadable > 0 { FeatureDiagnostics.record(.meeting, .fallback) }
    }
    self.records = loaded.enumerated().map { index, record in
      var normalized = record
      if normalized.sequenceNumber == nil { normalized.sequenceNumber = index + 1 }
      return normalized
    }.sorted { $0.startedAt > $1.startedAt }
  }

  /// Delete only a saved, inactive recording. Audio and transcripts share its folder.
  @discardableResult
  func deleteRecord(id: UUID) -> Bool {
    guard records.contains(where: { $0.id == id }),
          self.translatingRecordID != id,
          !(current?.id == id && (isRecording || isFinalizing)),
          let root = Self.meetingsDirectory() else { return false }
    let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
    do {
      try FileManager.default.removeItem(at: folder)
      records.removeAll { $0.id == id }
      if self.current?.id == id { self.current = nil }
      return true
    } catch {
      FeatureDiagnostics.record(.meeting, .failed)
      status = "Could not delete meeting recording"
      return false
    }
  }

  @discardableResult
  func deleteAllRecords() -> Bool {
    guard !self.isRecording, !self.isFinalizing, self.translatingRecordID == nil,
          let root = Self.meetingsDirectory() else { return false }
    do {
      try FileManager.default.removeItem(at: root)
      self.records = []
      self.current = nil
      return true
    } catch {
      FeatureDiagnostics.record(.meeting, .failed)
      self.status = "Could not delete meeting recordings"
      return false
    }
  }

  func meetingFolder(for record: MeetingRecord) -> URL? {
    Self.meetingsDirectory()?.appendingPathComponent(record.id.uuidString, isDirectory: true)
  }

  private static func meetingsDirectory() -> URL? {
    guard let group = AppGroup.containerURL else { return nil }
    let root = group.appendingPathComponent("meetings", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }
}


