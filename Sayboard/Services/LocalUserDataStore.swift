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
    ConfirmedChoiceLearning.chineseKey,
    CantoneseSchemePreference.candidateStorageKey,
    CantoneseSchemePreference.preferenceStorageKey,
    ConfirmedChoiceLearning.shapeWordKey,
    ConfirmedChoiceLearning.shapeGenerationKey,
    ConfirmedChoiceLearning.strokePrefixKey,
    ConfirmedChoiceLearning.latinKey
  ]

  static func resetLearning() {
    guard let defaults = AppGroup.sharedDefaults else { return }
    for key in self.learnedKeys { defaults.removeObject(forKey: key) }
    defaults.synchronize()
  }

  static func vocabularyData() throws -> Data {
    guard let defaults = AppGroup.sharedDefaults else {
      throw CocoaError(.fileReadNoSuchFile)
    }
    func counts(for key: String) -> [String: Int] {
      defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
    }
    let chinese = SharedSettings().cantoneseCorrectionRules.map {
      PersonalVocabularyExport.CorrectionEntry(
        language: "yue", heard: $0.heard, intended: $0.intended
      )
    }
    let latin = LatinSpeechCorrectionLearning.read(defaults: defaults).map {
      PersonalVocabularyExport.CorrectionEntry(
        language: $0.language, heard: $0.heard, intended: $0.intended
      )
    }
    return try PersonalVocabularyExport.encode(
      cantonese: counts(for: CantoneseSchemePreference.candidateStorageKey),
      latin: counts(for: ConfirmedChoiceLearning.latinKey),
      romanization: counts(for: CantoneseSchemePreference.preferenceStorageKey),
      confirmedChinese: ConfirmedChoiceLearning.chineseCounts(defaults: defaults),
      shapes: counts(for: ConfirmedChoiceLearning.shapeWordKey),
      shapeGenerations: counts(for: ConfirmedChoiceLearning.shapeGenerationKey),
      strokePrefixes: counts(for: ConfirmedChoiceLearning.strokePrefixKey),
      manualCorrections: chinese + latin
    )
  }

  static func delete(_ categories: [Category]) throws {
    FeatureDiagnostics.record(.data, .started)
    do {
      guard AppGroup.sharedDefaults != nil else { throw CocoaError(.fileWriteNoPermission) }
      for category in categories {
        switch category {
        case .voiceNotes:
          let removed = HistoryStore.shared.deleteAllRecords()
          if !removed, !(try HistoryStore.shared.readRecords()).isEmpty {
            throw CocoaError(.fileWriteUnknown)
          }
          // Include orphaned audio left by an interrupted or failed earlier cleanup.
          if let audio = HistoryStore.shared.audioDirectoryURL {
            try FileManager.default.removeItem(at: audio)
          }
        case .meetings:
          let recorder = MeetingRecordingCoordinator.shared
          guard recorder.deleteAllRecords() else { throw CocoaError(.fileWriteUnknown) }
        case .vocabulary:
          self.resetLearning()
          SharedSettings().cantoneseCorrectionRules = []
          AppGroup.sharedDefaults?.removeObject(forKey: LatinSpeechCorrectionLearning.storageKey)
          AppGroup.sharedDefaults?.synchronize()
        }
      }
    FeatureDiagnostics.record(.data, .completed)
    } catch {
      FeatureDiagnostics.record(.data, .failed)
      throw error
    }
  }

  static func export(_ categories: [Category]) async throws -> URL {
    FeatureDiagnostics.record(.data, .started)
    do {
      guard let group = AppGroup.containerURL else { throw CocoaError(.fileReadNoSuchFile) }
      let records = categories.contains(.voiceNotes) ? try HistoryStore.shared.readRecords() : []
      let historyData = try JSONEncoder().encode(records)
      let audioDirectory = HistoryStore.shared.audioDirectoryURL
      let vocabulary = categories.contains(.vocabulary) ? try self.vocabularyData() : nil
      // Copy and compress audio off the main actor; no recording enters memory as Data.
      let exportURL = try await Task.detached(priority: .userInitiated) {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = temporary.appendingPathComponent("Altboard-Data", isDirectory: true)
        do {
          try fm.createDirectory(at: folder, withIntermediateDirectories: true)
          if categories.contains(.voiceNotes) {
            let notes = folder.appendingPathComponent("Voice-Notes", isDirectory: true)
            try fm.createDirectory(at: notes, withIntermediateDirectories: true)
            try historyData.write(to: notes.appendingPathComponent("records.json"), options: .atomic)
            if let audio = audioDirectory, fm.fileExists(atPath: audio.path) {
              try fm.copyItem(at: audio, to: notes.appendingPathComponent("Audio", isDirectory: true))
            }
          }
          if categories.contains(.meetings) {
            let meetings = group.appendingPathComponent("meetings", isDirectory: true)
            if fm.fileExists(atPath: meetings.path) {
              try fm.copyItem(at: meetings, to: folder.appendingPathComponent("Meetings", isDirectory: true))
            }
          }
          if let vocabulary {
            try vocabulary.write(to: folder.appendingPathComponent("Vocabulary.json"), options: .atomic)
          }
          let archive = temporary.appendingPathComponent("Altboard-Data.zip")
          try fm.zipItem(at: folder, to: archive)
          try fm.removeItem(at: folder)
          try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: archive.path)
          return archive
        } catch {
          try? fm.removeItem(at: temporary)
          throw error
        }
      }.value
    FeatureDiagnostics.record(.data, .completed)
    return exportURL
    } catch {
      FeatureDiagnostics.record(.data, .failed)
      throw error
    }
  }
}
