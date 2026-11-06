import SwiftUI
import UniformTypeIdentifiers

/// User-controlled review and export. Nothing is sent to a service.
struct LearningDataSettingsView: View {
  @State private var showExporter = false
  @State private var exportedDocument: LearningDataExportDocument?
  @State private var showResetConfirmation = false
  @State private var exportError: String?
  @State private var counts = [String: Int]()

  var body: some View {
    Form {
      Section {
        LabeledContent("Confirmed words", value: "\(self.counts.count)")
        if self.counts.isEmpty {
          Text("No confirmed candidate selections are stored yet.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(self.topWords, id: \.key) { word in
            LabeledContent(word.key, value: "\(word.value)")
          }
        }
      } header: {
        Text("Learned Suggestions")
      } footer: {
        Text("Only chosen words and aggregate counts are learned. Altboard does not store full typed messages or gesture paths.")
      }

      Section {
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
      } header: {
        Text("Your Data")
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
    ) { result in
      if case .failure(let error) = result { self.exportError = error.localizedDescription }
      self.exportedDocument = nil
    }
    .alert("Data Export Failed", isPresented: Binding(
      get: { self.exportError != nil },
      set: { if !$0 { self.exportError = nil } }
    )) {
      Button("OK", role: .cancel) { self.exportError = nil }
    } message: {
      Text(self.exportError ?? "")
    }
  }

  private var topWords: [(key: String, value: Int)] {
    self.counts.sorted {
      $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
    }.prefix(12).map { (key: $0.key, value: $0.value) }
  }

  private func reload() {
    self.counts = AppGroup.sharedDefaults?.dictionary(forKey: LocalUserDataStore.learnedKeys[0]) as? [String: Int] ?? [:]
  }

  private func reset() {
    do {
      try LocalUserDataStore.resetLearning()
      self.reload()
    } catch {
      self.exportError = error.localizedDescription
    }
  }

  private func exportJSON() {
    do {
      let data = try LocalUserDataStore.vocabularyData()
      self.exportedDocument = LearningDataExportDocument(content: data)
      self.showExporter = true
    } catch {
      self.exportError = error.localizedDescription
    }
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

