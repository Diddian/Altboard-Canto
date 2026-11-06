import Foundation
import ZIPFoundation

@MainActor
enum LocalUserDataStore {
  enum Category: String, CaseIterable, Identifiable, Sendable {
    case voiceNotes, meetings, vocabulary
    var id: String { self.rawValue }
    var title: String {
      switch self {
      case .voiceNotes: "Voice Notes"
      case .meetings: "Meetings"
      case .vocabulary: "Corrections & Suggestions"
      }
    }
  }

  static let learnedKeys = [
    "canto.jyutping.selectionCounts",
    "canto.ime.schemePreferenceCounts.v1"
  ]

  static func vocabularyCount() -> Int {
    let defaults = AppGroup.sharedDefaults
    return learnedKeys.reduce(0) { $0 + (defaults?.dictionary(forKey: $1)?.count ?? 0) }
      + SharedSettings().cantoneseCorrectionRules.count
  }

  static func vocabularyData() throws -> Data {
    guard let defaults = AppGroup.sharedDefaults else { throw CocoaError(.fileReadNoSuchFile) }
    let selection = defaults.dictionary(forKey: learnedKeys[0]) as? [String: Int] ?? [:]
    let romanization = defaults.dictionary(forKey: learnedKeys[1]) as? [String: Int] ?? [:]
    let rules = Array(SharedSettings().cantoneseCorrectionRules.prefix(50)).map {
      PersonalVocabularyExport.CorrectionEntry(language: "yue",
                                                heard: $0.heard, intended: $0.intended)
    }
    let info = Bundle.main.infoDictionary ?? [:]
    let data = try PersonalVocabularyExport.encode(
      selections: selection, romanization: romanization, corrections: rules,
      version: info["CFBundleShortVersionString"] as? String ?? "unknown",
      build: info["CFBundleVersion"] as? String ?? "unknown",
      commit: info["AltboardBuildSHA"] as? String ?? "unstamped",
      keyboardCommit: defaults.string(forKey: SharedKey.keyboardBuildSHA) ?? "not reported"
    )
    guard data.count <= 2 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
    return data
  }

  static func resetLearning() throws {
    guard let defaults = AppGroup.sharedDefaults else { throw CocoaError(.fileWriteNoPermission) }
    for key in learnedKeys { defaults.removeObject(forKey: key) }
  }

  static func delete(_ categories: [Category]) throws {
    let selected = Set(categories)
    guard !selected.isEmpty else { throw CocoaError(.fileWriteUnknown) }
    guard AppGroup.sharedDefaults != nil, AppGroup.containerURL != nil else {
      throw CocoaError(.fileWriteNoPermission)
    }
    guard !MeetingRecordingCoordinator.shared.isRecording,
          !MeetingRecordingCoordinator.shared.isFinalizing else {
      throw CocoaError(.fileWriteNoPermission)
    }
    for category in Category.allCases where selected.contains(category) {
      switch category {
      case .voiceNotes:
        // Do not remove audio unless the manifest was persisted first.
        guard HistoryStore.shared.deleteAllRecords() else {
          throw CocoaError(.fileWriteUnknown)
        }
      case .meetings:
        guard MeetingRecordingCoordinator.shared.deleteAllRecords() else {
          throw CocoaError(.fileWriteUnknown)
        }
      case .vocabulary:
        try resetLearning()
        SharedSettings().cantoneseCorrectionRules = []
      }
    }
  }

  static func export(_ categories: [Category]) async throws -> URL {
    guard let group = AppGroup.containerURL, AppGroup.sharedDefaults != nil
    else { throw CocoaError(.fileReadNoSuchFile) }

    let selected = Set(categories)
    guard !selected.isEmpty else { throw CocoaError(.fileReadUnknown) }
    let records = selected.contains(.voiceNotes)
      ? try HistoryStore.shared.readRecords() : []
    // A bounded manifest; audio stays on disk and is copied, never loaded as Data.
    guard records.count <= 5_000 else { throw CocoaError(.fileReadTooLarge) }
    let encodedHistory = try JSONEncoder().encode(records)
    guard encodedHistory.count <= 64 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
    let audioRoot = selected.contains(.voiceNotes) ? HistoryStore.shared.audioDirectoryURL : nil
    let vocab = selected.contains(.vocabulary) ? try vocabularyData() : nil

    let archive = try await Task.detached(priority: .userInitiated) { () throws -> URL in
      let fm = FileManager.default
      let root = fm.temporaryDirectory.appendingPathComponent(
        "Altboard-export-" + UUID().uuidString, isDirectory: true)
      let contents = root.appendingPathComponent("Altboard-Data", isDirectory: true)
      do {
        try Task.checkCancellation()
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        if selected.contains(.voiceNotes) {
          let notes = contents.appendingPathComponent("Voice-Notes", isDirectory: true)
          try fm.createDirectory(at: notes, withIntermediateDirectories: true)
          try encodedHistory.write(to: notes.appendingPathComponent("records.json"), options: .atomic)
          if let audioRoot, fm.fileExists(atPath: audioRoot.path) {
            try fm.copyItem(at: audioRoot, to: notes.appendingPathComponent("Audio"))
          }
        }
        try Task.checkCancellation()
        if selected.contains(.meetings) {
          let dir = group.appendingPathComponent("meetings", isDirectory: true)
          if fm.fileExists(atPath: dir.path) {
            try fm.copyItem(at: dir, to: contents.appendingPathComponent("Meetings"))
          }
        }
        if let vocab {
          try vocab.write(to: contents.appendingPathComponent("Vocabulary.json"), options: .atomic)
        }
        try Task.checkCancellation()
        let url = root.appendingPathComponent("Altboard-Data.zip")
        try fm.zipItem(at: contents, to: url)
        try fm.removeItem(at: contents)
        try fm.setAttributes([.protectionKey: FileProtectionType.complete],
                             ofItemAtPath: url.path)
        try Task.checkCancellation()
        return url
      } catch {
        try? fm.removeItem(at: root)
        throw error
      }
    }.value
    return archive
  }
}
