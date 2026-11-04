import SwiftUI
import UIKit

private struct RetentionPolicyListView: View {

  @Binding var selected: HistoryRetentionPolicy

  var body: some View {
    List {
      ForEach(HistoryRetentionPolicy.allCases, id: \.self) { policy in
        self.policyRow(for: policy)
      }
    }
    .navigationTitle("Keep History")
    .navigationBarTitleDisplayMode(.inline)
  }

  @Environment(\.dismiss) private var dismiss
  @State private var pendingPolicy: HistoryRetentionPolicy?
  @State private var deletionCount = 0

  private func policyRow(for policy: HistoryRetentionPolicy) -> some View {
    Button {
      guard policy != self.selected else {
        self.dismiss()
        return
      }
      let count = HistoryStore.shared.recordsToDeleteCount(for: policy)
      if count > 0 {
        self.deletionCount = count
        self.pendingPolicy = policy
      } else {
        self.selected = policy
        self.dismiss()
      }
    } label: {
      HStack {
        Text(LocalizedStringKey(policy.displayNameKey))
        Spacer()
        if self.selected == policy {
          Image(systemName: "checkmark")
            .foregroundStyle(Color.accentColor)
            .fontWeight(.semibold)
        }
      }
    }
    .foregroundStyle(.primary)
    .confirmationDialog(
      "Delete Recordings",
      isPresented: self.isConfirmationPresented(for: policy),
      titleVisibility: .visible,
    ) {
      Button("Delete \(self.deletionCount)", role: .destructive) {
        self.selected = policy
        self.dismiss()
      }
    } message: {
      Text("This will permanently delete \(self.deletionCount) recordings and their audio files.")
    }
  }

  private func isConfirmationPresented(for policy: HistoryRetentionPolicy) -> Binding<Bool> {
    Binding(
      get: { self.pendingPolicy == policy },
      set: { if !$0 { self.pendingPolicy = nil } },
    )
  }
}


struct HistoryStorageSettingsView: View {
  init() {
    _selectedRetentionPolicy = State(initialValue: SharedSettings().retentionPolicy)
  }

  var body: some View {
    Form {
      Section("History") {
        NavigationLink {
          RetentionPolicyListView(selected: self.$selectedRetentionPolicy)
        } label: {
          LabeledContent {
            Text(LocalizedStringKey(self.selectedRetentionPolicy.shortDisplayNameKey))
              .foregroundStyle(.secondary)
          } label: {
            Label("Keep History", systemImage: "clock.arrow.circlepath")
          }
        }
        Button(role: .destructive) {
          self.showClearHistoryConfirmation = true
        } label: {
          Label("Clear All History", systemImage: "trash")
        }
        .confirmationDialog(
          "Clear All History",
          isPresented: self.$showClearHistoryConfirmation,
          titleVisibility: .visible
        ) {
          Button("Delete All Recordings", role: .destructive) {
            if HistoryStore.shared.deleteAllRecords() {
              self.historyClearedTrigger.toggle()
            } else {
              self.showHistoryDeletionError = true
            }
            self.refreshHistoryInfo()
          }
        } message: {
          Text(self.clearHistoryMessage)
        }
        if !self.historyInfoText.isEmpty {
          LabeledContent {
            Text(self.historyInfoText)
          } label: {
            Label("Stored History", systemImage: "externaldrive")
          }
        }
      }

      Section("Storage") {
        Button(role: .destructive) {
          self.showClearCacheConfirmation = true
        } label: {
          Label("Clear Compiled Model Cache", systemImage: "trash.slash")
        }
        .confirmationDialog(
          "Clear Compiled Model Cache",
          isPresented: self.$showClearCacheConfirmation,
          titleVisibility: .visible
        ) {
          Button("Clear Cache", role: .destructive) {
            ModelStorageManager.clearCompiledModelCache()
            self.refreshCacheSize()
            self.cacheClearedTrigger.toggle()
          }
        } message: {
          Text(self.clearCacheMessage)
        }
        if self.cacheSizeBytes > 0 {
          LabeledContent {
            Text(self.cacheSizeBytes.formatted(.byteCount(style: .file).locale(self.locale)))
          } label: {
            Label("Compiled Cache Size", systemImage: "internaldrive")
          }
        }
        Text("Clears compiled files only, not downloaded speech or text models.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("History & Storage")
    .navigationBarTitleDisplayMode(.inline)
    .alert("Unable to remove all recordings", isPresented: self.$showHistoryDeletionError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Some History data could not be removed. The app kept the existing records where possible.")
    }
    .sensoryFeedback(.success, trigger: self.historyClearedTrigger)
    .sensoryFeedback(.success, trigger: self.cacheClearedTrigger)
    .onAppear {
      self.refreshHistoryInfo()
      self.refreshCacheSize()
    }
    .onChange(of: self.selectedRetentionPolicy) { _, selected in
      SharedSettings().retentionPolicy = selected
      HistoryStore.shared.applyRetentionPolicy()
      self.refreshHistoryInfo()
    }
  }

  @Environment(\.locale) private var locale
  @State private var selectedRetentionPolicy: HistoryRetentionPolicy
  @State private var showClearHistoryConfirmation = false
  @State private var showHistoryDeletionError = false
  @State private var showClearCacheConfirmation = false
  @State private var historyInfoText = ""
  @State private var historyClearedTrigger = false
  @State private var cacheClearedTrigger = false
  @State private var cacheSizeBytes: Int64 = 0

  private let clearHistoryMessage: LocalizedStringKey =
    "All History recordings, their transcription text and audio files on this device will be permanently deleted."
  private let clearCacheMessage: LocalizedStringKey =
    "Compiled model files will be removed. They will be rebuilt on next use."

  private func refreshCacheSize() {
    self.cacheSizeBytes = ModelStorageManager.compiledModelCacheSize()
  }

  private func refreshHistoryInfo() {
    guard let count = try? HistoryStore.shared.readRecords().count, count > 0 else {
      self.historyInfoText = ""
      return
    }
    let bytes = HistoryStore.shared.audioStorageSize()
    let size = bytes > 0
      ? bytes.formatted(.byteCount(style: .file).locale(self.locale))
      : ""
    self.historyInfoText = size.isEmpty ? "\(count)" : "\(count) · \(size)"
  }
}
