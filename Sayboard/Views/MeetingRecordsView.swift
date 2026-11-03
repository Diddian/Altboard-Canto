import SwiftUI

struct MeetingRecordsView: View {
  @EnvironmentObject private var speechService: SpeechRecognitionService
  @ObservedObject private var recorder = MeetingRecordingCoordinator.shared
  @State private var pendingDeletion: UUID?
  @State private var draftTitle = ""
  @State private var draftNotes = ""

  var body: some View {
    Form {
      Section("Meeting Recording") {
        if self.recorder.isRecording {
          if let live = self.recorder.current {
            LabeledContent("Meeting", value: live.displayTitle)
          }
          LabeledContent("Elapsed", value: self.recorder.elapsed.formatted(.number.precision(.fractionLength(0))) + "s")
          Button("Stop & Save Meeting", role: .destructive) { self.recorder.stop() }
        } else {
          TextField("Meeting name (optional)", text: self.$draftTitle)
            .textInputAutocapitalization(.sentences)
          TextField("Meeting notes (optional)", text: self.$draftNotes, axis: .vertical)
            .lineLimit(2...4)
          Button("Start Meeting Recording") {
            self.recorder.start(
              with: self.speechService, title: self.draftTitle, notes: self.draftNotes
            )
            if self.recorder.isRecording {
              self.draftTitle = ""
              self.draftNotes = ""
            }
          }
        }
        Text(self.recorder.status).font(.footnote).foregroundStyle(.secondary)
        Text("Records continuously. Audio files rotate every 15 minutes; recognition updates about every 8 seconds when Qwen3-ASR 1.7B can keep up. Recording uses the same mic as dictation and cannot run simultaneously.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if let live = self.recorder.current, self.recorder.isRecording {
        Section("Live transcript (provisional)") {
          Text(live.transcript.isEmpty ? "Waiting for recognized speech…" : live.transcript)
            .textSelection(.enabled)
          Text("Saved audio parts: \(live.parts.count) complete + current part")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      Section("Meetings") {
        if self.recorder.records.isEmpty {
          Text("No saved meetings").foregroundStyle(.secondary)
        }
        ForEach(self.recorder.records) { record in
          NavigationLink {
            MeetingRecordDetailView(record: record)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(record.displayTitle)
              Text("\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(record.parts.count) audio parts · \(record.state)")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Delete", role: .destructive) {
              self.pendingDeletion = record.id
            }
          }
        }
      }
    }
    .confirmationDialog(
      "Delete Meeting?", isPresented: Binding(
        get: { self.pendingDeletion != nil },
        set: { if !$0 { self.pendingDeletion = nil } }
      ), titleVisibility: .visible
    ) {
      Button("Delete Meeting", role: .destructive) {
        if let id = self.pendingDeletion { self.recorder.deleteRecord(id: id) }
        self.pendingDeletion = nil
      }
      Button("Cancel", role: .cancel) { self.pendingDeletion = nil }
    } message: {
      Text("This permanently deletes the audio and transcript for this meeting.")
    }
    .navigationTitle("Meeting Records")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { self.recorder.reloadRecords() }
  }
}

private struct MeetingRecordDetailView: View {
  let record: MeetingRecord
  @ObservedObject private var recorder = MeetingRecordingCoordinator.shared
  @State private var name = ""
  @State private var notes = ""
  @State private var saved = false

  private var folder: URL? {
    MeetingRecordingCoordinator.shared.meetingFolder(for: self.record)
  }

  var body: some View {
    Form {
      Section("Meeting Notes") {
        TextField("Meeting name", text: self.$name)
          .textInputAutocapitalization(.sentences)
        TextField("Notes", text: self.$notes, axis: .vertical)
          .lineLimit(3...8)
        Button("Save Meeting Details") {
          self.saved = self.recorder.updateRecord(
            id: self.record.id, title: self.name, notes: self.notes
          )
        }
        if self.saved {
          Label("Saved", systemImage: "checkmark.circle")
            .foregroundStyle(.secondary)
        }
      }
      Section("Meeting") {
        LabeledContent("Started", value: self.record.startedAt.formatted(date: .abbreviated, time: .shortened))
        LabeledContent("Status", value: self.record.state)
        LabeledContent("Audio parts", value: "\(self.record.parts.count)")
      }
      Section("Combined Transcript") {
        Text(self.record.transcript.isEmpty ? "No transcript yet; saved audio is available below." : self.record.transcript)
          .textSelection(.enabled)
        if let url = self.folder?.appendingPathComponent("transcript.txt"),
           FileManager.default.fileExists(atPath: url.path) {
          ShareLink("Export Combined Transcript", item: url)
        }
      }
      Section("Audio Parts") {
        ForEach(self.record.parts) { part in
          if let url = self.folder?.appendingPathComponent("audio/" + part.fileName),
             FileManager.default.fileExists(atPath: url.path) {
            ShareLink(item: url) {
              LabeledContent("Part \(part.number)", value: "\(Int(part.duration))s")
            }
          } else {
            Text("Part \(part.number) unavailable").foregroundStyle(.secondary)
          }
        }
      }
    }
    .navigationTitle("Meeting Detail")
    .onAppear {
      self.name = self.record.title ?? ""
      self.notes = self.record.notes ?? ""
    }
  }
}
