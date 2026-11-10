import SwiftUI

struct HistoryRowView: View {

  let record: HistoryRecord
  let onDelete: () -> Void
  let onCorrection: (String) -> Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      self.headerRow
      if let source = self.record.originalASR,
         let target = self.record.outputLanguageCode, !target.isEmpty,
         !source.isEmpty, source != self.displayedText {
        VStack(alignment: .leading, spacing: 4) {
          Text("Original · ASR").font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(source).font(.body).foregroundStyle(.primary)
            .textSelection(.enabled)
          Text("Translation · \(target.uppercased())")
            .font(.caption.weight(.semibold)).foregroundStyle(.blue)
          self.transcriptionText.foregroundStyle(.blue)
        }
      } else {
        self.transcriptionText
      }
      self.audioPlayerControls
    }
    .padding(.vertical, 4)
    .sheet(isPresented: self.$isEditing) {
      self.correctionSheet
    }
  }

  @EnvironmentObject private var playerService: AudioPlayerService
  @State private var isExpanded = false
  @State private var copied = false
  @State private var isEditing = false
  @State private var correctedDraft = ""
  @State private var correctionError: String?
  @FocusState private var correctionFocused: Bool

  private var displayedText: String { self.record.displayedTranscription }

  private let truncationThreshold = 150
  private let truncationSuffixReserve = 20

  private var needsTruncation: Bool {
    self.displayedText.count > self.truncationThreshold
  }

  private var truncatedTranscription: String {
    let targetLength = self.truncationThreshold - self.truncationSuffixReserve
    let prefix = self.displayedText.prefix(targetLength)
    if let lastSpace = prefix.lastIndex(of: " ") {
      return String(prefix[prefix.startIndex..<lastSpace])
    }
    return String(prefix)
  }

  private var headerRow: some View {
    HStack {
      Text(self.record.date, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer()
      self.editButton
      self.copyButton
      self.deleteButton
    }
  }

  @ViewBuilder
  private var transcriptionText: some View {
    if self.displayedText.isEmpty {
      Text("No transcription")
        .font(.body)
        .foregroundStyle(.tertiary)
        .italic()
    } else if !self.needsTruncation {
      Text(self.displayedText)
        .font(.body)
        .onTapGesture { self.startCorrection() }
    } else if self.isExpanded {
      (Text(self.displayedText) + Text(" ") + Text("less").foregroundColor(.secondary))
        .font(.body)
        .onTapGesture {
          self.isExpanded = false
        }
    } else {
      (Text(self.truncatedTranscription) + Text("\u{2026} ") + Text("more").foregroundColor(.secondary))
        .font(.body)
        .onTapGesture {
          self.isExpanded = true
        }
    }
  }

  @ViewBuilder
  private var audioPlayerControls: some View {
    if let url = HistoryStore.shared.audioFileURL(for: record.audioFileName) {
      WaveformPlayerView(
        audioURL: url,
        totalDuration: self.record.duration,
        waveformSamples: self.record.waveformSamples,
        playerService: self.playerService,
      )
    }
  }

  private var editButton: some View {
    Button {
      self.startCorrection()
    } label: {
      Image(systemName: "pencil")
        .font(.system(size: 16))
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Correct recognized speech")
  }

  private var correctionSheet: some View {
    NavigationStack {
      Form {
        Section("Original ASR") {
          Text(self.record.originalASR ?? self.record.transcription)
            .font(.subheadline)
            .textSelection(.enabled)
        }
        Section("What was actually said") {
          TextEditor(text: self.$correctedDraft)
            .font(.body)
            .frame(minHeight: 140)
            .focused(self.$correctionFocused)
            .accessibilityLabel("Corrected spoken words")
          Text("Repeated, verified phrases improve local corrections. This does not retrain ASR model weights.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        if let correctionError {
          Label(correctionError, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red)
        }
      }
      .navigationTitle("Correct Transcript")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", systemImage: "xmark") {
            self.cancelCorrection()
          }
          .accessibilityHint("Dismisses the editor and keyboard without saving")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save & Learn") {
            self.correctionFocused = false
            if self.onCorrection(self.correctedDraft) {
              self.correctionError = nil
              self.isEditing = false
            } else {
              self.correctionError = "Unable to save locally. Check shared storage."
            }
          }
          .disabled(self.correctedDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .interactiveDismissDisabled(false)
      .onAppear { self.correctionFocused = true }
      .onDisappear { self.correctionFocused = false }
    }
  }

  private func cancelCorrection() {
    self.correctionFocused = false
    self.correctionError = nil
    self.isEditing = false
  }

  private func startCorrection() {
    self.correctedDraft = self.displayedText
    self.isEditing = true
    self.correctionError = nil
    self.correctionFocused = false
  }

  private var copyButton: some View {
    Button {
      UIPasteboard.general.string = self.displayedText
      withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
        self.copied = true
      }
      let delay = 0.75
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
          self.copied = false
        }
      }
    } label: {
      Image(self.copied ? "icon-check" : "icon-copy")
        .resizable()
        .frame(width: 18, height: 18)
        .foregroundStyle(self.copied ? .blue : .secondary)
        .scaleEffect(self.copied ? 1.2 : 1.0)
    }
    .buttonStyle(.plain)
    .disabled(self.displayedText.isEmpty)
  }

  private var deleteButton: some View {
    Button(role: .destructive) {
      self.onDelete()
    } label: {
      Image("icon-delete")
        .resizable()
        .frame(width: 18, height: 18)
        .foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)
  }
}
