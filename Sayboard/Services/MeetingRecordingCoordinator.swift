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
  var title: String? = nil
  var notes: String? = nil

  var totalDuration: TimeInterval { self.parts.reduce(0) { $0 + $1.duration } }
  var displayTitle: String {
    let name = (self.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? "Meeting " + self.startedAt.formatted(date: .abbreviated, time: .shortened) : name
  }
}

/// Opt-in experiment. No cloud uploads and no second microphone tap.
@MainActor
final class MeetingRecordingCoordinator: ObservableObject {
  static let shared = MeetingRecordingCoordinator()
  static let partDuration: TimeInterval = 15 * 60
  static let updateSeconds = 8

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

  func start(with service: SpeechRecognitionService) {
    guard !self.isRecording, !self.isFinalizing, !service.isRecording,
          SharedSettings().experimentalMeetingRecordEnabled,
          SharedSettings().selectedVariant == .qwen3ASR17B,
          let root = Self.meetingsDirectory() else {
      self.status = "Enable Meeting Record and select Qwen3-ASR 1.7B; stop other dictation first."
      return
    }
    do { try service.session.startSession() }
    catch { self.status = "Unable to activate microphone"; return }
    let id = UUID()
    let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
    let audioDirectory = folder.appendingPathComponent("audio", isDirectory: true)
    do { try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true) }
    catch { self.status = "Cannot create meeting storage"; return }
    let format = service.session.audioEngine.inputNode.outputFormat(forBus: 0)
    guard self.audioRecorder.startRecording(fileName: "0001.caf", format: format,
                                            directory: audioDirectory) != nil else {
      self.status = "Cannot open meeting audio file"
      return
    }
    self.speechService = service
    self.currentFormat = format
    self.currentAudioDirectory = audioDirectory
    self.current = MeetingRecord(id: id, startedAt: Date(), endedAt: nil,
                                 parts: [], transcript: "", state: "recording")
    self.lastPartStartedAt = Date()
    self.accumulator.reset()
    service.session.activateTap(accumulator: self.accumulator, recorder: self.audioRecorder)
    self.elapsed = 0
    self.isRecording = true
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

  private func saveManifest() {
    guard let record = self.current,
          let root = Self.meetingsDirectory(),
          let data = try? JSONEncoder().encode(record) else { return }
    let folder = root.appendingPathComponent(record.id.uuidString, isDirectory: true)
    let manifest = folder.appendingPathComponent("manifest.json")
    try? data.write(to: manifest, options: [.atomic, .completeFileProtectionUnlessOpen])
    let text = folder.appendingPathComponent("transcript.txt")
    try? record.transcript.write(to: text, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: text.path
    )
  }

  func reloadRecords() {
    guard let root = Self.meetingsDirectory(),
          let folders = try? FileManager.default.contentsOfDirectory(at: root,
                                              includingPropertiesForKeys: nil) else { return }
    self.records = folders.compactMap { folder -> MeetingRecord? in
      guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json"))
      else { return nil }
      return try? JSONDecoder().decode(MeetingRecord.self, from: data)
    }.sorted { $0.startedAt > $1.startedAt }
  }

  @discardableResult
  func updateRecord(id: UUID, title: String, notes: String) -> Bool {
    guard !self.isRecording, !self.isFinalizing,
          title.count <= 100, notes.count <= 2_000,
          let index = self.records.firstIndex(where: { $0.id == id }),
          let folder = self.meetingFolder(for: self.records[index]) else { return false }
    var record = self.records[index]
    record.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    record.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = try? JSONEncoder().encode(record) else { return false }
    do {
      try data.write(to: folder.appendingPathComponent("manifest.json"),
                     options: [.atomic, .completeFileProtectionUnlessOpen])
      self.records[index] = record
      return true
    } catch {
      return false
    }
  }

  @discardableResult
  func deleteRecord(id: UUID) -> Bool {
    guard !self.isRecording, !self.isFinalizing,
          let record = self.records.first(where: { $0.id == id }),
          let folder = self.meetingFolder(for: record) else { return false }
    do {
      try FileManager.default.removeItem(at: folder)
      self.reloadRecords()
      return true
    } catch { return false }
  }

  @discardableResult
  func deleteAllRecords() -> Bool {
    guard !self.isRecording, !self.isFinalizing else { return false }
    self.reloadRecords()
    var allRemoved = true
    for record in self.records {
      if !self.deleteRecord(id: record.id) { allRemoved = false }
    }
    return allRemoved
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
