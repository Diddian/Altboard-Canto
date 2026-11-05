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

  private let audioRecorder = AudioRecorder()
  private let accumulator = AudioBufferAccumulator()
  private weak var speechService: SpeechRecognitionService?
  private var currentFormat: AVAudioFormat?
  private var currentAudioDirectory: URL?
  private var lastPartStartedAt = Date()
  private var timer: Timer?
  private var decodeTask: Task<Void, Never>?
  private var sessionObservation: AnyCancellable?

  private init() { self.reloadRecords() }

  func start(with service: SpeechRecognitionService, title: String = "", notes: String = "") {
    guard !self.isRecording, !self.isFinalizing, !service.isRecording,
          SharedSettings().experimentalMeetingRecordEnabled,
          SharedSettings().selectedVariant == .qwen3ASR17B,
          let root = Self.meetingsDirectory() else {
      FeatureDiagnostics.record(.meeting, .blocked)
      self.status = "Enable Meeting Record and select Qwen3-ASR 1.7B; stop other dictation first."
      return
    }
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
      return
    }
    let format = service.session.audioEngine.inputNode.outputFormat(forBus: 0)
    guard self.audioRecorder.startRecording(fileName: "0001.caf", format: format,
                                            directory: audioDirectory) != nil else {
      FeatureDiagnostics.record(.meeting, .failed)
      self.status = "Cannot open meeting audio file"
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
    defaults.set(nextNumber, forKey: Self.meetingSequenceKey)
    self.lastPartStartedAt = Date()
    self.accumulator.reset()
    service.session.activateTap(accumulator: self.accumulator, recorder: self.audioRecorder)
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
        let result = await service.qwen3Service.transcribe(audioSamples: samples)
        // The current decoded chunk is still part of the saved meeting even
        // when Stop was pressed during the native inference call.
        if case .text(let output) = result {
          self.appendTranscript(output.text)
        }
      }
    }
  }

  func stop(interrupted: Bool = false) {
    guard self.isRecording else { return }
    self.isRecording = false
    self.timer?.invalidate()
    self.timer = nil
    let finishingDecode = self.decodeTask
    finishingDecode?.cancel()
    self.decodeTask = nil
    self.speechService?.session.deactivateTap()
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
      if let service, service.activeLoadState == .loaded {
        let remaining = self.accumulator.consumeAll()
        if !remaining.isEmpty {
          let result = await service.qwen3Service.transcribe(audioSamples: remaining)
          if case .text(let output) = result { self.appendTranscript(output.text) }
        }
      }
      if var record = self.current {
        record.endedAt = Date()
        record.state = interrupted ? "interrupted" : "completed"
        self.current = record
        self.saveManifest()
      }
      FeatureDiagnostics.record(.meeting, .completed)
      self.status = interrupted ? "Recording interrupted; saved available audio" : "Meeting saved"
      self.currentFormat = nil
      self.currentAudioDirectory = nil
      self.isFinalizing = false
      self.reloadRecords()
    }
  }

  private func heartbeat() {
    guard self.isRecording, let start = self.current?.startedAt else { return }
    self.elapsed = Date().timeIntervalSince(start)
    if Date().timeIntervalSince(self.lastPartStartedAt) >= Self.partDuration {
      self.closeCurrentPart()
      self.lastPartStartedAt = Date()
      guard let directory = self.currentAudioDirectory,
            let format = self.currentFormat,
            let count = self.current?.parts.count,
            self.audioRecorder.startRecording(fileName: String(format: "%04d.caf", count + 1),
                                              format: format, directory: directory) != nil else {
        FeatureDiagnostics.record(.meeting, .failed)
        self.status = "Audio file rotation failed"
        self.stop(interrupted: true)
        return
      }
      self.status = "Recording on iPhone — new 15-minute part"
    }
  }

  private func closeCurrentPart() {
    guard let saved = self.audioRecorder.stopRecording(),
          var record = self.current else { return }
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
  private func writeManifest(_ record: MeetingRecord) -> Bool {
    guard let root = Self.meetingsDirectory(),
          let data = try? JSONEncoder().encode(record) else {
      FeatureDiagnostics.record(.meeting, .failed)
      return false
    }
    let folder = root.appendingPathComponent(record.id.uuidString, isDirectory: true)
    let manifest = folder.appendingPathComponent("manifest.json")
    do {
      try data.write(to: manifest, options: [.atomic, .completeFileProtectionUnlessOpen])
      let transcriptURL = folder.appendingPathComponent("transcript.txt")
      try record.transcript.write(to: transcriptURL, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: transcriptURL.path
      )
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
    let loaded = folders.compactMap { folder -> MeetingRecord? in
      guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json"))
      else { return nil }
      return try? JSONDecoder().decode(MeetingRecord.self, from: data)
    }.sorted { $0.startedAt < $1.startedAt }
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
          !(current?.id == id && (isRecording || isFinalizing)),
          let root = Self.meetingsDirectory() else { return false }
    let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
    do {
      try FileManager.default.removeItem(at: folder)
      records.removeAll { $0.id == id }
      return true
    } catch {
      FeatureDiagnostics.record(.meeting, .failed)
      status = "Could not delete meeting recording"
      return false
    }
  }

  @discardableResult
  func deleteAllRecords() -> Bool {
    guard !self.isRecording, !self.isFinalizing,
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

