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
  @State private var selectedCategories = Set(LocalUserDataStore.Category.allCases)
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
      self.pendingRetentionPolicy == nil ? "Delete selected local data?" : "Delete older voice notes?",
      isPresented: self.$confirmDeletion, titleVisibility: .visible
    ) {
      if let policy = self.pendingRetentionPolicy {
        Button("Apply Retention", role: .destructive) { self.applyRetention(policy) }
      } else {
        Button("Delete", role: .destructive) { self.deleteSelected() }
      }
    } message: {
      Text(self.pendingRetentionPolicy == nil
        ? "Permanently delete only: \(self.pendingDeletion.map(\.title).joined(separator: ", ")). Other categories, models and settings stay untouched."
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
        Toggle(isOn: Binding(
          get: { self.selectedCategories.contains(category) },
          set: { enabled in
            if enabled { self.selectedCategories.insert(category) }
            else { self.selectedCategories.remove(category) }
          }
        )) {
          LabeledContent {
            Text("\(self.count(for: category))")
          } label: {
            Text(LocalizedStringKey(category.title))
          }
        }
        .disabled(self.busy || self.recordingActive)
      }
      Button("Select All Categories") {
        self.selectedCategories = Set(LocalUserDataStore.Category.allCases)
      }
      .disabled(self.busy || self.recordingActive
                || self.selectedCategories.count == LocalUserDataStore.Category.allCases.count)
      Picker("Keep Voice Notes", selection: self.retentionBinding) {
        ForEach(HistoryRetentionPolicy.allCases, id: \.self) { policy in
          Text(LocalizedStringKey(policy.shortDisplayNameKey)).tag(policy)
        }
      }
      .disabled(self.busy || self.recordingActive)
      Divider()
        .padding(.vertical, 4)
      VStack(alignment: .leading, spacing: 0) {
        Button {
          self.export(Array(self.selectedCategories))
        } label: {
          Label(self.busy ? "Preparing Export…" : "Export Selected Data",
                systemImage: "square.and.arrow.up")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(self.busy || self.recordingActive || self.selectedCategories.isEmpty)
        .frame(minHeight: 64)
        Divider().padding(.leading, 34)

        Button(role: .destructive) {
          self.pendingRetentionPolicy = nil
          self.pendingDeletion = Array(self.selectedCategories)
          self.confirmDeletion = true
        } label: {
          Label("Delete Selected Data", systemImage: "trash")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(self.busy || self.recordingActive || self.selectedCategories.isEmpty)
        .frame(minHeight: 64)
        Divider().padding(.leading, 34)

        Button(role: .destructive) {
          ModelStorageManager.clearCompiledModelCache()
        } label: {
          Label("Clear Model Cache", systemImage: "internaldrive")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(self.busy || self.recordingActive)
        .frame(minHeight: 64)

        Text("Only selected data categories are exported or deleted. Models and app settings are kept.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 12)
          .padding(.bottom, 10)
      }
      .padding(.vertical, 6)
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
    self.vocabularyCount = LocalUserDataStore.vocabularyCount()
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
    if !HistoryStore.shared.applyRetentionPolicy() {
      self.errorMessage = "Some voice notes could not be removed; check storage and exported backups."
    }
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

