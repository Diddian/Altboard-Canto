import Foundation

struct HistoryStore: Sendable {

  static let shared = Self()

  var audioDirectoryURL: URL? {
    guard let container = AppGroup.containerURL else { return nil }
    let audioDir = container.appendingPathComponent(self.audioDirectoryName)
    if !FileManager.default.fileExists(atPath: audioDir.path) {
      try? FileManager.default.createDirectory(
        at: audioDir,
        withIntermediateDirectories: true,
        attributes: [.protectionKey: FileProtectionType.completeUnlessOpen],
      )
    }
    return audioDir
  }

  func audioFileURL(for fileName: String) -> URL? {
    // Stored history can be imported or corrupted. Never resolve an audio
    // filename outside this app's private recordings directory.
    guard !fileName.isEmpty, fileName != ".", fileName != "..",
          !fileName.contains("/"), !fileName.contains("\\"),
          !fileName.contains("\0") else { return nil }
    return self.audioDirectoryURL?.appendingPathComponent(fileName, isDirectory: false)
  }

  func audioStorageSize() -> Int64 {
    guard let url = audioDirectoryURL else { return 0 }
    guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
    guard
      let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.fileSizeKey],
      )
    else {
      return 0
    }
    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
      if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
        total += Int64(size)
      }
    }
    return total
  }

  /// Raw index for a deliberate export when JSON decoding fails.
  /// Do not modify this file during recovery.
  var rawHistoryIndexURL: URL? { self.historyFileURL }

  func historyModificationDate() -> Date? {
    guard let url = historyFileURL else { return nil }
    return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
  }

  func loadRecords() -> [HistoryRecord] {
    (try? self.readRecords()) ?? []
  }

  func readRecords() throws -> [HistoryRecord] {
    guard let url = historyFileURL, FileManager.default.fileExists(atPath: url.path) else { return [] }
    let data = try Data(contentsOf: url)
    let records = try JSONDecoder.historyDecoder.decode([HistoryRecord].self, from: data)
    return records.sorted { $0.date > $1.date }
  }

  @discardableResult
  func saveRecord(_ record: HistoryRecord) -> Bool {
    guard SharedSettings().retentionPolicy != .never else {
      return self.deleteAudioFile(named: record.audioFileName)
    }
    guard var records = try? self.readRecords() else {
      self.preserveUnindexedRecord(record)
      FeatureDiagnostics.record(.data, .fallback)
      return false
    }
    records.insert(record, at: 0)
    guard self.writeRecords(records) else {
      self.preserveUnindexedRecord(record)
      FeatureDiagnostics.record(.data, .failed)
      return false
    }
    return true
  }

  @discardableResult
  func saveCorrectedTranscript(id: UUID, corrected: String) -> Bool {
    let text = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.count <= 10_000,
          var records = try? self.readRecords(),
          let index = records.firstIndex(where: { $0.id == id }) else {
      return false
    }
    let original = records[index]
    records[index] = original.withCorrection(
      text == original.transcription ? nil : text
    )
    guard self.writeRecords(records) else { return false }
    guard (try? self.readRecords().first(where: { $0.id == id })?
      .displayedTranscription) == text else { return false }

    // Derive a conservative phrase dictionary only from repeated explicit
    // corrections. This is local post-recognition learning, not weight updates.
    let candidates = SpeechCorrectionLearning.recurringPairs(in: records)
    if !candidates.isEmpty {
      let settings = SharedSettings()
      var rules = settings.cantoneseCorrectionRules
      for pair in candidates {
        guard rules.count < 50,
              !rules.contains(where: { $0.heard == pair.heard }) else { continue }
        rules.append(CantoneseCorrectionRule(
          heard: pair.heard, intended: pair.intended
        ))
        // Three independent, manually corrected recordings also provide
        // bounded positive evidence for a Chinese word across IME methods.
        // No full transcript or audio is copied into the keyboard profile.
        _ = ConfirmedChoiceLearning.rememberConfirmedChinese(
          pair.intended, defaults: AppGroup.sharedDefaults
        )
      }
      settings.cantoneseCorrectionRules = rules
      settings.synchronize()
    }
    let latinPairs = LatinSpeechCorrectionLearning.recurringRules(in: records)
    if !latinPairs.isEmpty {
      var learned = LatinSpeechCorrectionLearning.read(defaults: AppGroup.sharedDefaults)
      for candidate in latinPairs {
        guard learned.count < LatinSpeechCorrectionLearning.maximumRules,
              !learned.contains(where: {
                $0.language == candidate.language &&
                $0.heard.caseInsensitiveCompare(candidate.heard) == .orderedSame
              }) else { continue }
        learned.append(candidate)
      }
      LatinSpeechCorrectionLearning.save(learned, defaults: AppGroup.sharedDefaults)
    }
    return true
  }

  func deleteRecord(id: UUID) {
    guard var records = try? self.readRecords() else { return }
    guard let index = records.firstIndex(where: { $0.id == id }) else { return }
    let record = records[index]
    records.remove(at: index)
    guard self.writeRecords(records) else { return }
    self.deleteAudioFile(named: record.audioFileName)
  }

  @discardableResult
  func deleteAllRecords() -> Bool {
    guard let records = try? self.readRecords(),
          self.writeRecords([]) else { return false }
    var removedAll = true
    for record in records {
      if !self.deleteAudioFile(named: record.audioFileName) {
        removedAll = false
      }
    }
    return removedAll
  }

  func retainedRecords(
    for policy: HistoryRetentionPolicy,
    in records: [HistoryRecord],
    now: Date = Date(),
  ) -> [HistoryRecord] {
    switch policy {
    case .never: []
    case .last5: Array(records.prefix(self.countLimit5))
    case .last25: Array(records.prefix(self.countLimit25))
    case .last50: Array(records.prefix(self.countLimit50))
    case .last100: Array(records.prefix(self.countLimit100))
    case .last500: Array(records.prefix(self.countLimit500))
    case .past24Hours: self.records(in: records, newerThan: self.hoursInDay, from: now)
    case .pastWeek: self.records(in: records, newerThan: self.hoursInWeek, from: now)
    case .pastMonth: self.records(in: records, newerThan: self.hoursInMonth, from: now)
    case .forever: records
    }
  }

  func recordsToDeleteCount(for policy: HistoryRetentionPolicy) -> Int {
    let records = self.loadRecords()
    return records.count - self.retainedRecords(for: policy, in: records).count
  }

  func applyRetentionPolicy() {
    guard let records = try? self.readRecords() else { return }
    let retained = self.retainedRecords(for: SharedSettings().retentionPolicy, in: records)
    let retainedIDs = Set(retained.map(\.id))
    guard self.writeRecords(retained) else { return }
    for record in records where !retainedIDs.contains(record.id) {
      self.deleteAudioFile(named: record.audioFileName)
    }
  }

  private let historyFileName = "history.json"
  private let audioDirectoryName = "audio"

  private let countLimit5 = 5
  private let countLimit25 = 25
  private let countLimit50 = 50
  private let countLimit100 = 100
  private let countLimit500 = 500

  private let hoursInDay = 24
  private let hoursInWeek = 168
  private let hoursInMonth = 720

  private var historyFileURL: URL? {
    AppGroup.containerURL?.appendingPathComponent(self.historyFileName)
  }

  @discardableResult
  private func writeRecords(_ records: [HistoryRecord]) -> Bool {
    guard let url = historyFileURL,
          let data = try? JSONEncoder.historyEncoder.encode(records) else {
      return false
    }
    do {
      try data.write(to: url, options: [.atomic, .completeFileProtection])
      return true
    } catch {
      return false
    }
  }

  /// Keep metadata beside the recorded audio if the primary history index
  /// cannot be read or written. Data export includes this private audio folder.
  private func preserveUnindexedRecord(_ record: HistoryRecord) {
    guard let folder = self.audioDirectoryURL,
          let data = try? JSONEncoder.historyEncoder.encode(record) else { return }
    let url = folder.appendingPathComponent("unindexed-\(record.id.uuidString).json")
    do {
      try data.write(to: url, options: [.atomic, .completeFileProtection])
    } catch {
      FeatureDiagnostics.record(.data, .failed)
    }
  }

  @discardableResult
  private func deleteAudioFile(named fileName: String) -> Bool {
    guard let url = audioFileURL(for: fileName) else { return false }
    guard FileManager.default.fileExists(atPath: url.path) else { return true }
    do {
      try FileManager.default.removeItem(at: url)
      return true
    } catch {
      return false
    }
  }

  private func records(in records: [HistoryRecord], newerThan hours: Int, from now: Date) -> [HistoryRecord] {
    let cutoff = now.addingTimeInterval(-Double(hours) * 3600)
    return records.filter { $0.date >= cutoff }
  }
}

extension JSONDecoder {
  fileprivate static let historyDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}

extension JSONEncoder {
  fileprivate static let historyEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .prettyPrinted
    return encoder
  }()
}
