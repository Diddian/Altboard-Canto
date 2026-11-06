import SwiftUI
import UIKit

struct MeetingRecordsView: View {
  @EnvironmentObject private var speechService: SpeechRecognitionService
  @ObservedObject private var recorder = MeetingRecordingCoordinator.shared
  @State private var searchText = ""
  @State private var pendingDelete: UUID?
  @State private var editingID: UUID?
  @State private var editingTitle = ""
  @State private var editingNotes = ""
  @State private var showModelNotice = false
  @State private var showError = false

  private var filteredRecords: [MeetingRecord] {
    guard !self.searchText.isEmpty else { return self.recorder.records }
    return self.recorder.records.filter {
      $0.displayTitle.localizedCaseInsensitiveContains(self.searchText)
        || $0.transcript.localizedCaseInsensitiveContains(self.searchText)
        || ($0.notes ?? "").localizedCaseInsensitiveContains(self.searchText)
    }
  }

  var body: some View {
    List {
      if self.recorder.isRecording {
        Section("Recording") {
          LabeledContent("Elapsed", value: String(Int(self.recorder.elapsed)) + "s")
          Button("Stop & Save Meeting", role: .destructive) { self.recorder.stop() }
          Text(self.recorder.status).font(.footnote).foregroundStyle(.secondary)
        }
      } else {
        Section {
          Button {
            let settings = SharedSettings()
            guard settings.selectedVariant == .qwen3ASR17B, settings.hasUsableModel else {
              self.showModelNotice = true
              return
            }
            settings.experimentalMeetingRecordEnabled = true
            self.recorder.start(with: self.speechService)
          } label: {
            Label("Start Meeting Recording", systemImage: "record.circle")
          }
          .disabled(self.recorder.isFinalizing)
        }
      }
      Section("Meetings") {
        if self.filteredRecords.isEmpty {
          Text("No saved meetings").foregroundStyle(.secondary)
        }
        ForEach(self.filteredRecords) { record in
          HStack {
            NavigationLink {
              MeetingRecordDetailView(record: record)
            } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(record.displayTitle)
                Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
            Menu {
              Button("Rename & Notes", systemImage: "pencil") {
                self.editingID = record.id
                self.editingTitle = record.title ?? ""
                self.editingNotes = record.notes ?? ""
              }
              Button("Delete", systemImage: "trash", role: .destructive) {
                self.pendingDelete = record.id
              }
            } label: { Image(systemName: "ellipsis.circle") }
              .accessibilityLabel("Meeting options")
              .disabled(self.recorder.isRecording || self.recorder.isFinalizing)
          }
        }
      }
    }
    .navigationTitle("Meetings")
    .searchable(text: self.$searchText, prompt: "Search meetings")
    .onAppear { self.recorder.reloadRecords() }
    .confirmationDialog("Delete meeting?",
      isPresented: Binding(get: { self.pendingDelete != nil },
                           set: { if !$0 { self.pendingDelete = nil } })) {
      Button("Delete Meeting", role: .destructive) {
        if let id = self.pendingDelete { self.showError = !self.recorder.deleteRecord(id: id) }
        self.pendingDelete = nil
      }
      Button("Cancel", role: .cancel) { self.pendingDelete = nil }
    } message: { Text("Saved audio and transcripts will be removed.") }
    .alert("Edit Meeting", isPresented: Binding(get: { self.editingID != nil },
                                                set: { if !$0 { self.editingID = nil } })) {
      TextField("Name", text: self.$editingTitle)
      TextField("Notes", text: self.$editingNotes)
      Button("Save") {
        if let id = self.editingID {
          self.showError = !self.recorder.updateRecord(
            id: id, title: self.editingTitle, notes: self.editingNotes)
        }
        self.editingID = nil
      }
      .disabled(self.editingTitle.count > 100 || self.editingNotes.count > 2_000)
      Button("Cancel", role: .cancel) { self.editingID = nil }
    } message: { Text("Only the name and notes will change.") }
    .alert("Recording model required", isPresented: self.$showModelNotice) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Download and select Qwen3-ASR 1.7B in Settings → Speech Model.")
    }
    .alert("Unable to save changes", isPresented: self.$showError) {
      Button("OK", role: .cancel) {}
    }
  }
}

struct MeetingRecordDetailView: View {
  let record: MeetingRecord
  @ObservedObject private var recorder = MeetingRecordingCoordinator.shared
  @State private var title = ""
  @State private var notes = ""
  @State private var showError = false

  private var current: MeetingRecord {
    self.recorder.records.first(where: { $0.id == self.record.id }) ?? self.record
  }
  private var folder: URL? { self.recorder.meetingFolder(for: self.current) }

  var body: some View {
    Form {
      Section("Meeting") {
        TextField("Name", text: self.$title)
        TextField("Notes", text: self.$notes, axis: .vertical).lineLimit(2...5)
        Button("Save Name & Notes") {
          self.showError = !self.recorder.updateRecord(id: self.record.id,
                                                        title: self.title, notes: self.notes)
        }
        .disabled(self.recorder.isRecording || self.recorder.isFinalizing
                  || self.title.count > 100 || self.notes.count > 2_000)
        LabeledContent("Started",
          value: self.current.startedAt.formatted(date: .abbreviated, time: .shortened))
        LabeledContent("Duration", value: String(Int(self.current.totalDuration)) + "s")
      }
      Section("Combined Transcript") {
        Text(self.current.transcript.isEmpty ? "No transcript" : self.current.transcript)
          .textSelection(.enabled)
        if let url = self.folder?.appendingPathComponent("transcript.txt"),
           FileManager.default.fileExists(atPath: url.path) {
          ShareLink("Share Transcript", item: url)
        }
      }
      Section("Audio Parts") {
        ForEach(self.current.parts) { part in
          if !part.fileName.contains("/"), !part.fileName.contains("\\"),
             let url = self.folder?.appendingPathComponent("audio/" + part.fileName),
             FileManager.default.fileExists(atPath: url.path) {
            ShareLink(item: url) {
              LabeledContent("Part " + String(part.number),
                value: String(Int(part.duration)) + "s")
            }
          }
        }
      }
    }
    .navigationTitle(self.current.displayTitle)
    .onAppear {
      self.title = self.current.title ?? ""
      self.notes = self.current.notes ?? ""
    }
    .alert("Unable to save changes", isPresented: self.$showError) {
      Button("OK", role: .cancel) {}
    }
  }
}
