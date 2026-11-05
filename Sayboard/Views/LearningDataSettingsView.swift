import SwiftUI
import UniformTypeIdentifiers

/// User-controlled review and export. Nothing is sent to a service.
struct LearningDataSettingsView: View {
  @State private var showExporter = false
  @State private var exportedDocument: LearningDataExportDocument?
  @State private var showResetConfirmation = false
  @State private var counts = [String: Int]()

  var body: some View {
    Form {
      Section("Learned Suggestions") {
        LabeledContent("Confirmed words", value: "\(self.counts.count)")
        if self.counts.isEmpty {
          Text("Choose a word in the keyboard to begin building personal suggestions.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(self.topWords, id: \.key) { word in
            LabeledContent(word.key, value: "\(word.value)")
          }
        }
      } footer: {
        Text("Only chosen words and aggregate counts are learned. Altboard does not store full typed messages or gesture paths.")
      }

      Section("Your Data") {
        Button {
          self.exportJSON()
        } label: {
          Label("Export Corrections & Suggestions (JSON)", systemImage: "square.and.arrow.up")
        }
        .disabled(AppGroup.sharedDefaults == nil)

        Button(role: .destructive) {
          self.showResetConfirmation = true
        } label: {
          Label("Reset Learned Suggestions", systemImage: "arrow.counterclockwise")
        }
        .disabled(AppGroup.sharedDefaults == nil)
      } footer: {
        Text("Export includes explicit speech correction pairs and aggregate keyboard preferences, but not recordings or transcripts. Reset only affects learned keyboard selections; it does not delete recordings, speech correction rules or downloaded models.")
      }
    }
    .navigationTitle("Learned Suggestions")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { self.reload() }
    .confirmationDialog(
      "Reset Learned Suggestions?", isPresented: self.$showResetConfirmation,
      titleVisibility: .visible
    ) {
      Button("Reset Learned Selections", role: .destructive) { self.reset() }
    } message: {
      Text("This removes personal word and input-method selection counts, but keeps speech corrections and recordings.")
    }
    .fileExporter(
      isPresented: self.$showExporter,
      document: self.exportedDocument,
      contentType: .json,
      defaultFilename: "Altboard-Corrections-and-Suggestions"
    ) { _ in
      self.exportedDocument = nil
    }
  }

  private var topWords: [(key: String, value: Int)] {
    self.counts.sorted {
      $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }.prefix(12).map { (key: $0.key, value: $0.value) }
  }

  private func reload() {
    self.counts = ConfirmedChoiceLearning.chineseCounts(defaults: AppGroup.sharedDefaults)
  }

  private func reset() {
    guard let defaults = AppGroup.sharedDefaults else { return }
    for key in [
      ConfirmedChoiceLearning.chineseKey,
      CantoneseSchemePreference.candidateStorageKey,
      CantoneseSchemePreference.preferenceStorageKey,
      ConfirmedChoiceLearning.shapeWordKey,
      ConfirmedChoiceLearning.shapeGenerationKey,
      ConfirmedChoiceLearning.strokePrefixKey,
      ConfirmedChoiceLearning.latinKey
    ] {
      defaults.removeObject(forKey: key)
    }
    defaults.synchronize()
    self.reload()
  }

  private func exportJSON() {
    guard let defaults = AppGroup.sharedDefaults else { return }
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
    guard let data = try? PersonalVocabularyExport.encode(
      cantonese: counts(for: CantoneseSchemePreference.candidateStorageKey),
      latin: counts(for: ConfirmedChoiceLearning.latinKey),
      romanization: counts(for: CantoneseSchemePreference.preferenceStorageKey),
      confirmedChinese: ConfirmedChoiceLearning.chineseCounts(defaults: defaults),
      shapes: counts(for: ConfirmedChoiceLearning.shapeWordKey),
      shapeGenerations: counts(for: ConfirmedChoiceLearning.shapeGenerationKey),
      strokePrefixes: counts(for: ConfirmedChoiceLearning.strokePrefixKey),
      manualCorrections: chinese + latin
    ) else { return }
    self.exportedDocument = LearningDataExportDocument(content: data)
    self.showExporter = true
  }
}

private struct LearningDataExportDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  let content: Data

  init(content: Data) { self.content = content }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    self.content = data
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: self.content)
  }
}
