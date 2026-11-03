import SwiftUI

struct MeetingRecordsView: View {
  @EnvironmentObject private var speechService: SpeechRecognitionService
  @ObservedObject private var recorder = MeetingRecordingCoordinator.shared

  var body: some View {
    Form {
      Section("Experimental Recording") {
        if self.recorder.isRecording {
          LabeledContent("Elapsed", value: self.recorder.elapsed.formatted(.number.precision(.fractionLength(0))) + "s")
          Button("Stop & Save Meeting", role: .destructive) { self.recorder.stop() }
        } else {
          Button("Start Meeting Recording") { self.recorder.start(with: self.speechService) }
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
              Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
              Text("\(record.parts.count) audio parts · \(record.state)")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .navigationTitle("Meeting Records")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { self.recorder.reloadRecords() }
  }
}

private struct MeetingRecordDetailView: View {
  let record: MeetingRecord

  private var folder: URL? {
    MeetingRecordingCoordinator.shared.meetingFolder(for: self.record)
  }

  var body: some View {
    Form {
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
  }
}
