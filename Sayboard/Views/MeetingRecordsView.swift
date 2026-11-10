import SwiftUI
import UIKit

/// A Voice Memos-style list, without destructive audio-editing features.
struct MeetingRecordsView: View {
  @EnvironmentObject private var speechService: SpeechRecognitionService
  @ObservedObject private var recorder = MeetingRecordingCoordinator.shared
  @StateObject private var playback = MeetingAudioPlayback()

  @State private var searchText = ""
  @State private var searchPresented = false
  @State private var expandedID: UUID?
  @State private var pendingDelete: UUID?
  @State private var renamingID: UUID?
  @State private var renameText = ""
  @State private var showModelNotice = false
  @State private var operationError: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var filteredRecords: [MeetingRecord] {
    guard !self.searchText.isEmpty else { return self.recorder.records }
    return self.recorder.records.filter {
      $0.displayTitle.localizedCaseInsensitiveContains(self.searchText)
        || $0.transcript.localizedCaseInsensitiveContains(self.searchText)
    }
  }

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 14) {
        self.explanationCard
        if let operationError = self.operationError {
          HStack {
            Label(operationError, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange)
            Spacer()
            Button("Dismiss") { self.operationError = nil }
          }
          .accessibilityElement(children: .contain)
        }
        if self.recorder.unreadableRecordCount > 0 {
          Label(
            "\(self.recorder.unreadableRecordCount) meeting folder(s) could not be loaded. "
              + "Original files are preserved. Export data before deleting anything.",
            systemImage: "externaldrive.badge.exclamationmark"
          )
          .font(.footnote)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
        }
        if self.recorder.isRecording, let current = self.recorder.current {
          self.activeMeetingCard(current)
        }
        if self.filteredRecords.isEmpty && !self.recorder.isRecording {
          ContentUnavailableView(
            self.searchText.isEmpty ? "No meetings yet" : "No matching meetings",
            systemImage: "person.3",
            description: Text("Record locally, then rename and share the combined transcript.")
          )
          .padding(.top, 35)
        }
        ForEach(self.filteredRecords) { record in
          self.meetingRow(record)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 14)
      .padding(.bottom, 14)
    }
    .navigationTitle("Meetings")
    .navigationBarTitleDisplayMode(.large)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button {
          self.searchPresented = true
        } label: {
          Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel("Search meetings")
        Button {
          self.recordAction()
        } label: {
          Image(systemName: self.recorder.isRecording ? "stop.circle.fill" : "square.and.pencil")
        }
        .disabled(self.recorder.isFinalizing || self.recorder.translatingRecordID != nil)
        .accessibilityLabel(self.recorder.isRecording ? "Stop and save meeting" : "Start a new meeting")
      }
    }
    .searchable(
      text: self.$searchText, isPresented: self.$searchPresented,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "Search meetings"
    )
    .safeAreaInset(edge: .bottom, spacing: 0) {
      HStack {
        Spacer(minLength: 0)
        self.recordButton
        Spacer(minLength: 0)
      }
      .padding(.vertical, 12)
      .background(.ultraThinMaterial)
    }
    .onAppear { self.recorder.reloadRecords() }
    .onDisappear { self.playback.stop() }
    .confirmationDialog(
      "Delete meeting?", isPresented: Binding(
        get: { self.pendingDelete != nil },
        set: { if !$0 { self.pendingDelete = nil } }
      ), titleVisibility: .visible
    ) {
      Button("Delete Meeting", role: .destructive) {
        if let id = self.pendingDelete {
          if self.playback.recordID == id { self.playback.stop() }
          if !self.recorder.deleteRecord(id: id) {
            self.operationError = "Unable to delete meeting. The saved files were not confirmed removed."
          }
        }
        self.pendingDelete = nil
      }
      Button("Cancel", role: .cancel) { self.pendingDelete = nil }
    } message: {
      Text("The saved audio parts and combined transcript will be deleted.")
    }
    .alert("Rename Meeting", isPresented: Binding(
      get: { self.renamingID != nil },
      set: { if !$0 { self.renamingID = nil } }
    )) {
      TextField("Meeting name", text: self.$renameText)
      Button("Save") {
        if let id = self.renamingID,
           let original = self.recorder.records.first(where: { $0.id == id }) {
          if !self.recorder.updateRecord(
            id: id, title: self.renameText, notes: original.notes ?? ""
          ) {
            self.operationError = "Unable to rename meeting. Try again."
          }
        }
        self.renamingID = nil
      }
      Button("Cancel", role: .cancel) { self.renamingID = nil }
    }
    .alert("Meeting Model Needed", isPresented: self.$showModelNotice) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Meeting recording requires a downloaded speech model. Open Settings → Speech & AI → Speech Models to select one.")
    }
  }

  private var explanationCard: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "waveform.badge.mic")
        .foregroundStyle(.blue)
        .font(.title2)
      VStack(alignment: .leading, spacing: 6) {
        Text("Your meetings, on your iPhone")
          .font(.headline)
        Text("Audio is saved in 15-minute parts. Offline transcription updates about every 8 seconds when the model can keep up. A single combined transcript is saved when you stop; copy or share it anywhere.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 18))
    .accessibilityElement(children: .combine)
  }

  private func activeMeetingCard(_ record: MeetingRecord) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Circle().fill(.red).frame(width: 9, height: 9)
        Text(record.displayTitle).font(.headline)
        Spacer()
        Text(Self.time(self.recorder.elapsed))
          .monospacedDigit()
      }
      Text(self.recorder.status)
        .font(.caption).foregroundStyle(.secondary)
      if !record.transcript.isEmpty {
        Text(record.transcript)
          .font(.subheadline)
          .lineLimit(4)
          .textSelection(.enabled)
      } else {
        Text("Waiting for live transcript…")
          .font(.subheadline).foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
  }

  @ViewBuilder
  private func meetingRow(_ record: MeetingRecord) -> some View {
    VStack(spacing: 12) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 5) {
          Button {
            withAnimation(self.reduceMotion ? nil : .easeInOut(duration: 0.16)) {
              if self.expandedID == record.id {
                self.expandedID = nil
              } else {
                self.expandedID = record.id
              }
              self.playback.stop()
            }
          } label: {
            Text(record.displayTitle)
              .font(.headline)
              .foregroundStyle(.primary)
              .lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Playback controls for \(record.displayTitle)")
          .accessibilityHint("Expand or collapse playback controls")
          HStack(spacing: 8) {
            Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
            if !record.transcript.isEmpty {
              NavigationLink {
                MeetingRecordDetailView(record: record)
              } label: {
                Image(systemName: "quote.bubble")
              }
              .accessibilityLabel("View transcript for \(record.displayTitle)")
            }
          }
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text(Self.time(record.totalDuration))
          .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
          .accessibilityLabel("Duration \(Self.time(record.totalDuration))")
        Menu {
          Button("Rename", systemImage: "pencil") {
            self.renameText = record.title ?? ""
            self.renamingID = record.id
          }
          NavigationLink {
            MeetingRecordDetailView(record: record)
          } label: {
            Label("Transcript & Files", systemImage: "text.alignleft")
          }
          Button("Delete", systemImage: "trash", role: .destructive) {
            self.pendingDelete = record.id
          }
        } label: {
          Image(systemName: "ellipsis")
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Meeting options for \(record.displayTitle)")
      }

      if self.expandedID == record.id {
        self.expandedPlayer(record)
      }
    }
    .padding(15)
    .background(Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 17))
  }

  private func expandedPlayer(_ record: MeetingRecord) -> some View {
    VStack(spacing: 8) {
      Slider(
        value: Binding(
          get: {
            self.playback.recordID == record.id ? self.playback.position : 0
          },
          set: {
            self.playback.seek(to: $0, in: record)
          }
        ),
        in: 0...max(1, record.totalDuration)
      )
      .disabled(record.parts.isEmpty)
      .accessibilityLabel("Playback position for \(record.displayTitle)")
      HStack {
        Text(Self.time(self.playback.recordID == record.id ? self.playback.position : 0))
        Spacer()
        Text("-" + Self.time(max(0, record.totalDuration
          - (self.playback.recordID == record.id ? self.playback.position : 0))))
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
      HStack {
        NavigationLink {
          MeetingRecordDetailView(record: record)
        } label: {
          Image(systemName: "quote.bubble")
            .font(.title3)
        }
        .accessibilityLabel("View transcript for \(record.displayTitle)")
        .frame(minWidth: 44, minHeight: 44)
        Spacer()
        Button {
          self.playback.skip(-15, in: record)
        } label: {
          Image(systemName: "gobackward.15").font(.title2)
        }
        .accessibilityLabel("Back 15 seconds")
        .frame(minWidth: 44, minHeight: 44)
        Spacer()
        Button {
          self.playback.toggle(record)
        } label: {
          Image(systemName: self.playback.recordID == record.id
            && self.playback.isPlaying ? "pause.fill" : "play.fill")
            .font(.system(size: 28, weight: .semibold))
            .frame(minWidth: 48, minHeight: 48)
        }
        .disabled(record.parts.isEmpty)
        .accessibilityLabel(self.playback.recordID == record.id && self.playback.isPlaying
          ? "Pause meeting audio" : "Play meeting audio")
        Spacer()
        Button {
          self.playback.skip(15, in: record)
        } label: {
          Image(systemName: "goforward.15").font(.title2)
        }
        .accessibilityLabel("Forward 15 seconds")
        .frame(minWidth: 44, minHeight: 44)
        Spacer()
        Button(role: .destructive) {
          self.pendingDelete = record.id
        } label: {
          Image(systemName: "trash").font(.title3)
        }
        .accessibilityLabel("Delete \(record.displayTitle)")
        .frame(minWidth: 44, minHeight: 44)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.primary)
      .padding(.vertical, 5)
    }
  }

  private var recordButton: some View {
    Button {
      self.recordAction()
    } label: {
      ZStack {
        Circle()
          .fill(Color(uiColor: .tertiarySystemBackground))
          .frame(width: 78, height: 78)
        Circle()
          .fill(Color.red)
          .frame(width: 64, height: 64)
        if self.recorder.isRecording {
          RoundedRectangle(cornerRadius: 5)
            .fill(.white).frame(width: 24, height: 24)
        }
      }
    }
    .buttonStyle(.plain)
    .disabled(self.recorder.isFinalizing || self.recorder.translatingRecordID != nil)
    .accessibilityLabel(self.recorder.isRecording ? "Stop and save meeting" : "Record meeting")
  }

  private func recordAction() {
    if self.recorder.isRecording {
      self.recorder.stop()
      return
    }
    let settings = SharedSettings()
    guard settings.hasUsableModel else {
      self.showModelNotice = true
      return
    }
    self.playback.stop()
    // Tapping Record is the user's explicit opt-in to this feature.
    settings.experimentalMeetingRecordEnabled = true
    self.recorder.start(with: self.speechService)
  }

  static func time(_ seconds: TimeInterval) -> String {
    let whole = max(0, Int(seconds.isFinite ? seconds : 0))
    return String(format: "%d:%02d", whole / 60, whole % 60)
  }
}

private struct MeetingRecordDetailView: View {
  let record: MeetingRecord
  @EnvironmentObject private var speechService: SpeechRecognitionService
  // Per-record translation must not silently change the global keyboard output.
  @State private var meetingTarget = VoiceOutputTarget.cantonese
  @State private var outputLanguage = "tr"
  @ObservedObject private var recorder = MeetingRecordingCoordinator.shared
  @State private var name = ""
  @State private var notes = ""
  @State private var saved = false
  @State private var saveFailed = false
  @State private var showingFullOriginal = false
  @State private var showingFullTranslation = false

  private var latest: MeetingRecord {
    self.recorder.records.first(where: { $0.id == self.record.id }) ?? self.record
  }

  private var selectedTarget: VoiceOutputTarget { self.meetingTarget }

  private var originalPreview: String {
    let text = self.latest.transcript
    guard !text.isEmpty else { return "The transcript will appear here after recognition finishes." }
    return String(text.prefix(450)) + (text.count > 450 ? "…" : "")
  }

  private var translatedPreview: String {
    let text = self.latest.translatedTranscript ?? ""
    return String(text.prefix(340)) + (text.count > 340 ? "…" : "")
  }

  private var translationOptions: VoiceOutputConfiguration {
    let settings = SharedSettings()
    let options = settings.voiceOutputConfiguration
    return VoiceOutputConfiguration(
      cleanupEnabled: options.cleanupEnabled,
      target: self.selectedTarget,
      register: options.register,
      customLanguage: self.selectedTarget == .custom ? self.outputLanguage : "",
      punctuationEnabled: options.punctuationEnabled
    )
  }

  private var canTranslate: Bool {
    self.selectedTarget != .original &&
      (self.selectedTarget != .custom ||
       VoiceOutputTarget.customLanguageName(self.outputLanguage) != nil)
  }

  private var selectedLanguageName: String {
    let label = self.selectedTarget.title
    return self.selectedTarget == .custom ? "\(label) (\(self.outputLanguage))" : label
  }

  private var folder: URL? {
    self.recorder.meetingFolder(for: self.latest)
  }

  var body: some View {
    Form {
      Section("Meeting") {
        TextField("Name", text: self.$name)
          .textInputAutocapitalization(.sentences)
        TextField("Notes (optional)", text: self.$notes, axis: .vertical)
          .lineLimit(2...5)
        Button("Save Name & Notes") {
          self.saved = self.recorder.updateRecord(
            id: self.record.id, title: self.name, notes: self.notes
          )
          self.saveFailed = !self.saved
        }
        if self.saved { Label("Saved", systemImage: "checkmark.circle") }
        if self.saveFailed {
          Label("Unable to save meeting details. Try again.", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        }
        LabeledContent("Started", value: self.latest.startedAt.formatted(
          date: .abbreviated, time: .shortened))
        LabeledContent("Duration", value: MeetingRecordsView.time(self.latest.totalDuration))
        Text("Saved privately on this iPhone in Altboard → Meetings. Use Share to export a copy.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section("Original Transcript") {
        if self.latest.state == "partialTranscript" {
          Label("Transcript incomplete. Original audio parts are preserved.",
                systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        }
        if self.latest.state == "partialAudio" {
          Label("Some audio could not be saved. Available parts and transcript are preserved.",
                systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        }
        Text(self.originalPreview)
          .foregroundStyle(.primary)
          .lineLimit(7)
          .textSelection(.enabled)
        if self.latest.transcript.count > 450 {
          Button("Read Full Original Transcript") { self.showingFullOriginal = true }
        }
        Text("Source: Automatically recognized speech")
          .font(.caption)
          .foregroundStyle(.secondary)
        Button("Copy Transcript") {
          UIPasteboard.general.string = self.latest.transcript
        }
        .disabled(self.latest.transcript.isEmpty)
        if let transcript = self.folder?.appendingPathComponent("transcript.txt"),
           FileManager.default.fileExists(atPath: transcript.path) {
          ShareLink("Share Transcript", item: transcript)
        }
      }
      Section("Translation") {
        Picker("Translate to", selection: self.$meetingTarget) {
          Text("Cantonese · YUE").tag(VoiceOutputTarget.cantonese)
          Text("English · EN").tag(VoiceOutputTarget.english)
          Text("German · DE").tag(VoiceOutputTarget.german)
          Text("Written Chinese · ZH").tag(VoiceOutputTarget.traditionalChinese)
          Text("Other language").tag(VoiceOutputTarget.custom)
        }
        .disabled(self.recorder.translatingRecordID == self.record.id)
        if self.selectedTarget == .custom {
          TextField("Language code, e.g. tr, ja, ar", text: self.$outputLanguage)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .disabled(self.recorder.translatingRecordID == self.record.id)
          if VoiceOutputTarget.customLanguageName(self.outputLanguage) == nil {
            Text("Enter a valid two- or three-letter language code.")
              .font(.footnote)
              .foregroundStyle(.orange)
          }
        }
        if let translated = self.latest.translatedTranscript, !translated.isEmpty {
          LabeledContent("Saved output language",
                         value: self.latest.translatedLanguageCode ?? "Unknown")
          Text(self.translatedPreview)
            .foregroundStyle(.blue)
            .lineLimit(6)
            .textSelection(.enabled)
          if translated.count > 340 {
            Button("Read Full Translation") { self.showingFullTranslation = true }
          }
          Button("Copy Translation") { UIPasteboard.general.string = translated }
          Text("Saved with this meeting on your iPhone; the original remains unchanged.")
            .font(.footnote).foregroundStyle(.secondary)
        }
        if let draft = self.latest.translationDraftText, !draft.isEmpty {
          Text("Translation preview · Saved sections")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(String(draft.prefix(340)) + (draft.count > 340 ? "…" : ""))
            .foregroundStyle(.blue)
            .lineLimit(6)
            .textSelection(.enabled)
        }
        if let count = self.latest.translationDraftNextChunk, count > 0 {
          Label("Saved \(count) translated sections. Tap Translate to resume.",
                systemImage: "arrow.clockwise")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        if self.recorder.translatingRecordID == self.record.id {
          ProgressView(self.recorder.translationStatus)
          Button("Pause Translation") {
            self.recorder.cancelTranslation(id: self.record.id)
          }
          .accessibilityHint("Preserves original transcript and saved translated sections")
        } else {
          Button("Translate to \(self.selectedLanguageName)") {
            self.recorder.translateRecord(
              id: self.record.id, using: self.speechService,
              options: self.translationOptions
            )
          }
          .disabled(!self.canTranslate || self.latest.transcript.isEmpty
            || self.recorder.translatingRecordID != nil
            || self.recorder.isRecording || self.recorder.isFinalizing)
          Text("Offline translation saves separately; your original audio and transcript stay intact.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          if !self.recorder.translationStatus.isEmpty {
            Text(self.recorder.translationStatus)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
      }
      if let turns = self.latest.conversationTurns, !turns.isEmpty {
        Section("Conversation Turns") {
          ForEach(turns) { turn in
            VStack(alignment: .leading, spacing: 6) {
              Text(turn.speaker.title)
                .font(.headline)
              HStack {
                Text("Original · ASR").font(.caption.weight(.semibold))
                Spacer()
                Text(turn.detectedLanguageCode?.uppercased() ?? "AUTO")
                  .font(.caption.monospaced())
              }
              .foregroundStyle(.secondary)
              Text(turn.sourceText.isEmpty ? "Audio saved; recognition pending." : turn.sourceText)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
              if let translated = turn.translatedText, !translated.isEmpty {
                Text("Translation · " + turn.targetCode.uppercased())
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.blue)
                Text(translated)
                  .foregroundStyle(.blue)
                  .textSelection(.enabled)
              }
            }
            .padding(.vertical, 6)
          }
        }
      }
      Section("Saved Audio Parts") {
        ForEach(self.latest.parts) { part in
          if !part.fileName.contains("/"), !part.fileName.contains("\\"),
             let url = self.folder?.appendingPathComponent(
              "audio/" + part.fileName
             ),
             FileManager.default.fileExists(atPath: url.path) {
            ShareLink(item: url) {
              LabeledContent("Part \(part.number)",
                             value: MeetingRecordsView.time(part.duration))
            }
          } else {
            Text("Part \(part.number) unavailable")
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .navigationTitle(self.latest.displayTitle)
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: self.$showingFullOriginal) {
      NavigationStack {
        ScrollView {
          Text(self.latest.transcript)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(16)
        }
        .navigationTitle("Original Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { self.showingFullOriginal = false }
          }
        }
      }
    }
    .sheet(isPresented: self.$showingFullTranslation) {
      NavigationStack {
        ScrollView {
          Text(self.latest.translatedTranscript ?? "")
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(16)
        }
        .navigationTitle("Translation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { self.showingFullTranslation = false }
          }
        }
      }
    }
    .onAppear {
      self.name = self.latest.title ?? ""
      self.notes = self.latest.notes ?? ""
    }
    .onChange(of: self.name) { _, _ in self.saved = false; self.saveFailed = false }
    .onChange(of: self.notes) { _, _ in self.saved = false; self.saveFailed = false }
  }
}
