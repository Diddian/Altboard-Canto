import SwiftUI
import UIKit

struct DataAndStorageSettingsView: View {
  var inline = false
  @EnvironmentObject private var speechService: SpeechRecognitionService
  @Environment(\.locale) private var locale
  @Environment(\.scenePhase) private var scenePhase
  @ObservedObject private var recorder = MeetingRecordingCoordinator.shared
  @State private var retentionPolicy = SharedSettings().retentionPolicy
  @State private var pendingRetentionPolicy: HistoryRetentionPolicy?
  @State private var voiceNoteCount = 0
  @State private var vocabularyCount = 0
  @State private var pendingDeletion: [LocalUserDataStore.Category] = []
  @State private var confirmDeletion = false
  @State private var confirmCacheClear = false
  @State private var confirmTemporaryDelete = false
  @State private var busy = false
  @State private var exportTask: Task<Void, Never>?
  @State private var exportURL: URL?
  @State private var errorMessage: String?
  @State private var storage: StorageUsageSnapshot?
  @State private var storageRefreshID = UUID()
  @State private var storageScanning = true
  @State private var storageScanFailed = false

  private var recordingActive: Bool {
    LocalUserDataStore.hasActiveOperation
      || self.speechService.isRecording || self.speechService.isStopping
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
          .navigationTitle(Text("Storage & Usage", tableName: "Storage"))
          .navigationBarTitleDisplayMode(.inline)
      }
    }
    .onAppear { self.reload(refreshStorage: false) }
    .task(id: self.storageRefreshID) { await self.scanStorage() }
    .onChange(of: self.scenePhase) { _, phase in
      if phase == .active { self.storageRefreshID = UUID() }
    }
    .onDisappear {
      // The share sheet still owns its temporary file until dismissal.
      self.exportTask?.cancel()
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
        ? (self.pendingDeletion.contains(.vocabulary)
          ? "This permanently deletes learned selections, personal corrections and vocabulary as well as any other selected records. Export a copy first. This cannot be undone."
          : "Permanently delete the selected records. Learned vocabulary is kept unless separately selected.")
        : "Voice notes outside the selected retention period will be permanently deleted.")
    }
    .confirmationDialog("Delete Old Temporary Files?",
      isPresented: self.$confirmTemporaryDelete, titleVisibility: .visible
    ) {
      Button("Delete Old Temporary Files", role: .destructive) {
        self.deleteOldTemporaryFiles()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Only regular files over one hour old in Altboard's temporary directory will be deleted. Recordings, models, settings and learned vocabulary are not touched.")
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
      self.storageOverview
      if let storage = self.storage {
        self.storedFiles(storage.inventory)
      }
      Divider().padding(.vertical, 4)
      Text("Manage Local Data", tableName: "Storage")
        .font(.headline)
      ForEach(LocalUserDataStore.Category.allCases) { category in
        HStack {
          LabeledContent {
            Text("\(self.count(for: category))")
          } label: {
            Text(LocalizedStringKey(category.title))
          }
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
      Divider()
        .padding(.vertical, 4)
      VStack(alignment: .leading, spacing: 0) {
        Button { self.export(LocalUserDataStore.Category.allCases) } label: {
          Label {
            Text(LocalizedStringKey(self.busy ? "Preparing Export…" : "Export All Data"))
          } icon: {
            Image(systemName: "square.and.arrow.up")
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(self.busy || self.recordingActive)
        .frame(minHeight: 64)
        Divider().padding(.leading, 34)

        Button(role: .destructive) {
          self.pendingRetentionPolicy = nil
          self.pendingDeletion = LocalUserDataStore.Category.allCases
          self.confirmDeletion = true
        } label: {
          Label("Delete All Data, Including Learning", systemImage: "trash")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(self.busy || self.recordingActive)
        .frame(minHeight: 64)
        Divider().padding(.leading, 34)

        Button(role: .destructive) {
          self.confirmCacheClear = true
        } label: {
          Label("Clear Model Cache", systemImage: "internaldrive")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(self.busy || self.recordingActive)
        .frame(minHeight: 64)
        .confirmationDialog(
          "Clear Compiled Model Cache?",
          isPresented: self.$confirmCacheClear,
          titleVisibility: .visible
        ) {
          Button("Clear Cache", role: .destructive) {
            guard !self.recordingActive, !self.busy else { return }
            ModelStorageManager.clearCompiledModelCache()
            self.storageRefreshID = UUID()
          }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("The compiled cache will be rebuilt when needed. Downloaded models are kept.")
        }

        Text("Exports include recordings, transcripts and vocabulary. Models and app settings are kept.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 12)
          .padding(.bottom, 10)
      }
      .padding(.vertical, 6)
    }
  }

  private var storageOverview: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Device Storage", tableName: "Storage").font(.headline)
        Spacer(minLength: 8)
        if self.storageScanning {
          ProgressView()
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(Text("Measuring Storage", tableName: "Storage"))
        } else {
          Button { self.storageRefreshID = UUID() } label: {
            Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44)
          }
          .accessibilityLabel(Text("Refresh Storage", tableName: "Storage"))
        }
      }
      if let device = self.storage?.device {
        Text("\(self.formattedBytes(device.usedBytes)) of \(self.formattedBytes(device.totalBytes)) used",
          tableName: "Storage")
          .font(.subheadline)
          .monospacedDigit()
          .fixedSize(horizontal: false, vertical: true)
        ProgressView(value: device.usedFraction)
          .tint(.accentColor)
          .accessibilityLabel(Text("Device Storage", tableName: "Storage"))
          .accessibilityValue(Text(device.usedFraction, format: .percent.precision(.fractionLength(1))))
        ViewThatFits(in: .horizontal) {
          HStack {
            self.usedPercentage(device)
            Spacer(minLength: 12)
            self.availableStorage(device)
          }
          VStack(alignment: .leading, spacing: 4) {
            self.usedPercentage(device)
            self.availableStorage(device)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      } else if !self.storageScanning {
        Text("Device capacity is unavailable.", tableName: "Storage")
          .font(.subheadline).foregroundStyle(.secondary)
      }
      if self.storageScanFailed {
        if self.storage == nil {
          Text("Storage could not be measured. Tap refresh to try again.", tableName: "Storage")
            .font(.footnote).foregroundStyle(.secondary)
        } else {
          Text("Storage could not be refreshed. The previous measurement is shown.", tableName: "Storage")
            .font(.footnote).foregroundStyle(.secondary)
        }
      } else if self.storageScanning {
        Text("Measuring files on this iPhone…", tableName: "Storage")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if let storage = self.storage {
        Divider()
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline) {
            Text("Altboard Files", tableName: "Storage").font(.headline)
            Spacer(minLength: 12)
            self.appStorageTotal(storage.inventory)
          }
          VStack(alignment: .leading, spacing: 4) {
            Text("Altboard Files", tableName: "Storage").font(.headline)
            self.appStorageTotal(storage.inventory)
          }
        }
        if storage.inventory.totalBytes > 0 {
          self.appStorageBar(storage.inventory)
        }
        Text("Includes the app installation and shared keyboard files. System-managed storage outside the app is excluded. Totals may differ from iOS Settings.",
          tableName: "Storage")
          .font(.footnote).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if storage.isIncomplete {
          Label {
            Text("Some files could not be measured. This total is incomplete.", tableName: "Storage")
          } icon: {
            Image(systemName: "exclamationmark.triangle")
          }
          .font(.footnote).foregroundStyle(.secondary)
        }
        if storage.inventory.usedSizeFallback {
          Text("Some file sizes are estimates because allocated space was unavailable.", tableName: "Storage")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 6)
  }

  private func usedPercentage(_ device: DeviceStorageUsage) -> some View {
    Text("\(device.usedFraction.formatted(.percent.precision(.fractionLength(1)).locale(self.locale))) used",
      tableName: "Storage")
  }

  private func availableStorage(_ device: DeviceStorageUsage) -> some View {
    Text("\(self.formattedBytes(device.availableBytes)) available", tableName: "Storage")
  }

  private func appStorageTotal(_ inventory: StorageUsageInventory) -> some View {
    Text(self.formattedBytes(inventory.totalBytes))
      .font(.title3.weight(.semibold))
      .monospacedDigit()
  }

  private func appStorageBar(_ inventory: StorageUsageInventory) -> some View {
    GeometryReader { geometry in
      HStack(spacing: 0) {
        ForEach(StorageUsageCategory.allCases) { category in
          let fraction = Double(inventory.bytes(for: category)) / Double(inventory.totalBytes)
          self.storageColor(category)
            .frame(width: geometry.size.width * fraction)
        }
      }
      .clipShape(Capsule())
    }
    .frame(height: 10)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func storedFiles(_ inventory: StorageUsageInventory) -> some View {
    if inventory.items.isEmpty {
      Text("No measurable files found.", tableName: "Storage")
        .foregroundStyle(.secondary)
    } else {
      Text("Files on This iPhone", tableName: "Storage").font(.headline)
      Text("Models include files still downloading or awaiting cleanup. Expand a row to inspect its files.",
        tableName: "Storage")
        .font(.footnote).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      ForEach(inventory.items) { item in
        if item.category == .cache {
          HStack(alignment: .center, spacing: 8) {
            self.storageItemDescription(item)
            Spacer(minLength: 4)
            self.storageItemSize(item)
            Button(role: .destructive) {
              self.confirmTemporaryDelete = true
            } label: {
              Image(systemName: "trash")
                .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Delete Old Temporary Files")
            .disabled(self.busy || self.recordingActive || self.exportURL != nil)
          }
          .padding(.vertical, 4)
        } else {
          DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
              ForEach(item.files) { file in
                VStack(alignment: .leading, spacing: 2) {
                  Text(verbatim: file.name)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                  Text(self.formattedBytes(file.bytes))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
              }
              if item.fileCount > item.files.count {
                Text("Showing the largest files. Total includes all measured files.", tableName: "Storage")
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
            .padding(.vertical, 8)
          } label: {
            ViewThatFits(in: .horizontal) {
              HStack(alignment: .firstTextBaseline, spacing: 8) {
                self.storageItemDescription(item)
                Spacer(minLength: 4)
                self.storageItemSize(item)
              }
              VStack(alignment: .leading, spacing: 4) {
                self.storageItemDescription(item)
                self.storageItemSize(item)
              }
            }
            .padding(.vertical, 4)
            .frame(minHeight: 44)
          }
        }
      }
    }
  }

  private func storageItemDescription(_ item: StorageUsageItem) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Circle().fill(self.storageColor(item.category)).frame(width: 8, height: 8)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        if let name = item.modelName {
          Text(verbatim: name)
        } else {
          Text(LocalizedStringKey(item.category.titleKey), tableName: "Storage")
        }
        if item.modelName != nil {
          Text(LocalizedStringKey(item.category.titleKey), tableName: "Storage")
            .font(.caption).foregroundStyle(.secondary)
        }
        HStack(spacing: 4) {
          Text("Files", tableName: "Storage")
          Text(item.fileCount, format: .number)
        }
        .font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func storageItemSize(_ item: StorageUsageItem) -> some View {
    Text(self.formattedBytes(item.bytes))
      .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
      .fixedSize()
  }

  private func storageColor(_ category: StorageUsageCategory) -> Color {
    switch category {
    case .appInstallation: .red
    case .speechModels: .blue
    case .textModels: .purple
    case .compiledModels: .orange
    case .voiceNotes: .green
    case .meetings: .teal
    case .conversationDraft: .cyan
    case .cache: .yellow
    case .settings: .indigo
    case .diagnostics: .pink
    case .other: .gray
    }
  }

  private func formattedBytes(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file).locale(self.locale))
  }

  @MainActor
  private func scanStorage() async {
    self.storageScanning = true
    self.storageScanFailed = false
    defer {
      if !Task.isCancelled { self.storageScanning = false }
    }
    do {
      let result = try await StorageUsageService.scan()
      try Task.checkCancellation()
      self.storage = result
    } catch is CancellationError {
      // SwiftUI cancels this task when the destination closes or refreshes.
    } catch {
      if !Task.isCancelled { self.storageScanFailed = true }
    }
  }

  private func count(for category: LocalUserDataStore.Category) -> Int {
    switch category {
    case .voiceNotes: self.voiceNoteCount
    case .meetings: self.recorder.records.count
    case .vocabulary: self.vocabularyCount
    case .conversationDraft: ConversationCoordinator.shared.turns.count
    }
  }

  private func reload(refreshStorage: Bool = true) {
    do { self.voiceNoteCount = try HistoryStore.shared.readRecords().count }
    catch { self.errorMessage = error.localizedDescription }
    self.recorder.reloadRecords()
    let defaults = AppGroup.sharedDefaults
    self.vocabularyCount = LocalUserDataStore.learnedKeys.reduce(0) {
      $0 + (defaults?.dictionary(forKey: $1)?.count ?? 0)
    } + SharedSettings().cantoneseCorrectionRules.count
      + LatinSpeechCorrectionLearning.read(defaults: defaults).count
    if refreshStorage { self.storageRefreshID = UUID() }
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

  private func deleteOldTemporaryFiles() {
    guard !self.recordingActive, !self.busy, self.exportURL == nil else { return }
    do {
      _ = try LocalUserDataStore.deleteOldTemporaryFiles()
      self.storageRefreshID = UUID()
    } catch {
      self.errorMessage = "Temporary-file cleanup failed: \(error.localizedDescription)"
    }
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
    self.storageRefreshID = UUID()
  }
}

private struct DataExportSheet: UIViewControllerRepresentable {
  let url: URL
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [self.url], applicationActivities: nil)
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}


