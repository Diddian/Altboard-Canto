import SwiftUI
import UIKit

struct DataAndStorageSettingsView: View {
  var inline = false
  @EnvironmentObject private var speechService: SpeechRecognitionService
  @ObservedObject private var recorder = MeetingRecordingCoordinator.shared
  @State private var retentionPolicy = SharedSettings().retentionPolicy
  @State private var pendingRetentionPolicy: HistoryRetentionPolicy?
  @State private var voiceNoteCount = 0
  @State private var vocabularyCount = 0
  @State private var pendingDeletion: [LocalUserDataStore.Category] = []
  @State private var confirmDeletion = false
  @State private var busy = false
  @State private var exportTask: Task<Void, Never>?
  @State private var exportURL: URL?
  @State private var errorMessage: String?

  private var recordingActive: Bool {
    self.speechService.isRecording || self.speechService.isStopping
      || self.recorder.isRecording || self.recorder.isFinalizing
  }

  var body: some View {
    Group {
      if self.inline {
        VStack(alignment: .leading, spacing: 12) { self.rows }
          .pickerStyle(.menu)
          .buttonStyle(.borderless)
      } else {
        Form { self.rows }
          .navigationTitle("History & Storage")
          .navigationBarTitleDisplayMode(.inline)
      }
    }
    .onAppear { self.reload() }
    .onDisappear {
      self.exportTask?.cancel()
      self.clearExport()
    }
    .confirmationDialog(
      self.pendingRetentionPolicy == nil ? "Delete Local Data?" : "Delete Older Voice Notes?",
      isPresented: self.$confirmDeletion, titleVisibility: .visible
    ) {
      if let policy = self.pendingRetentionPolicy {
        Button("Apply Retention", role: .destructive) { self.applyRetention(policy) }
      } else {
        Button("Delete", role: .destructive) { self.deleteSelected() }
      }
    } message: {
      Text(self.pendingRetentionPolicy == nil
        ? "Permanently delete the selected recordings, transcripts or vocabulary. Export a copy first if you need one."
        : "Voice notes outside the selected retention period will be permanently deleted.")
    }
    .alert("Data Operation Failed", isPresented: Binding(
      get: { self.errorMessage != nil },
      set: { if !$0 { self.errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) { self.errorMessage = nil }
    } message: {
      Text(self.errorMessage ?? "")
    }
    .sheet(isPresented: Binding(
      get: { self.exportURL != nil },
      set: { if !$0 { self.clearExport() } }
    ), onDismiss: { self.clearExport() }) {
      if let url = self.exportURL { DataExportSheet(url: url) }
    }
  }

  @ViewBuilder
  private var rows: some View {
    Group {
      ForEach(LocalUserDataStore.Category.allCases) { category in
        HStack {
          LabeledContent(category.title, value: "\(self.count(for: category))")
          Menu {
            Button("Export", systemImage: "square.and.arrow.up") { self.export([category]) }
            Button("Delete", systemImage: "trash", role: .destructive) {
              self.pendingRetentionPolicy = nil
              self.pendingDeletion = [category]
              self.confirmDeletion = true
            }
          } label: {
            Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
          }
          .accessibilityLabel("Manage \(category.title)")
          .disabled(self.busy || self.recordingActive)
        }
      }
      Picker("Keep Voice Notes", selection: self.retentionBinding) {
        ForEach(HistoryRetentionPolicy.allCases, id: \.self) { policy in
          Text(LocalizedStringKey(policy.shortDisplayNameKey)).tag(policy)
        }
      }
      .disabled(self.busy || self.recordingActive)
      Button { self.export(LocalUserDataStore.Category.allCases) } label: {
        Label(self.busy ? "Preparing Export…" : "Export All Data", systemImage: "square.and.arrow.up")
      }
      .disabled(self.busy || self.recordingActive)
      Button(role: .destructive) {
        self.pendingRetentionPolicy = nil
        self.pendingDeletion = LocalUserDataStore.Category.allCases
        self.confirmDeletion = true
      } label: {
        Label("Delete All Data", systemImage: "trash")
      }
      .disabled(self.busy || self.recordingActive)
      Button("Clear Model Cache", role: .destructive) {
        ModelStorageManager.clearCompiledModelCache()
      }
      .disabled(self.busy || self.recordingActive)
      Text("Exports include recordings, transcripts and vocabulary. Models and app settings are kept.")
        .font(.footnote).foregroundStyle(.secondary)
    }
  }

  private func count(for category: LocalUserDataStore.Category) -> Int {
    switch category {
    case .voiceNotes: self.voiceNoteCount
    case .meetings: self.recorder.records.count
    case .vocabulary: self.vocabularyCount
    }
  }

  private func reload() {
    do { self.voiceNoteCount = try HistoryStore.shared.readRecords().count }
    catch { self.errorMessage = error.localizedDescription }
    self.recorder.reloadRecords()
    let defaults = AppGroup.sharedDefaults
    self.vocabularyCount = LocalUserDataStore.learnedKeys.reduce(0) {
      $0 + (defaults?.dictionary(forKey: $1)?.count ?? 0)
    } + SharedSettings().cantoneseCorrectionRules.count
      + LatinSpeechCorrectionLearning.read(defaults: defaults).count
  }

  private var retentionBinding: Binding<HistoryRetentionPolicy> {
    Binding(get: { self.retentionPolicy }, set: { policy in
      if HistoryStore.shared.recordsToDeleteCount(for: policy) > 0 {
        self.pendingRetentionPolicy = policy
        self.confirmDeletion = true
      } else {
        self.applyRetention(policy)
      }
    })
  }

  private func applyRetention(_ policy: HistoryRetentionPolicy) {
    guard !self.recordingActive, !self.busy else { return }
    self.retentionPolicy = policy
    SharedSettings().retentionPolicy = policy
    HistoryStore.shared.applyRetentionPolicy()
    self.reload()
  }

  private func deleteSelected() {
    guard !self.recordingActive, !self.busy else { return }
    do { try LocalUserDataStore.delete(self.pendingDeletion) }
    catch { self.errorMessage = "Deletion was incomplete. Some data may remain. \(error.localizedDescription)" }
    self.reload()
  }

  private func export(_ categories: [LocalUserDataStore.Category]) {
    guard !self.recordingActive, !self.busy else { return }
    self.busy = true
    self.exportTask = Task { @MainActor in
      defer { self.busy = false }
      do {
        let url = try await LocalUserDataStore.export(categories)
        if Task.isCancelled {
          try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        } else {
          self.exportURL = url
        }
      } catch {
        if !Task.isCancelled { self.errorMessage = error.localizedDescription }
      }
    }
  }

  private func clearExport() {
    guard let url = self.exportURL else { return }
    self.exportURL = nil
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
  }
}

private struct DataExportSheet: UIViewControllerRepresentable {
  let url: URL
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [self.url], applicationActivities: nil)
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

