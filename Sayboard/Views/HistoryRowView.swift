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
          if self.isEditing {
            self.correctionEditor
          } else {
            self.transcriptionText.foregroundStyle(.blue)
          }
        }
      } else if self.isEditing {
        self.correctionEditor
      } else {
        self.transcriptionText
      }
      self.audioPlayerControls
    }
    .padding(.vertical, 4)
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

  private var correctionEditor: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Correct Transcript")
        .font(.subheadline.weight(.semibold))
      TextEditor(text: self.$correctedDraft)
        .font(.body)
        .frame(minHeight: 110, maxHeight: 210)
        .focused(self.$correctionFocused)
        .accessibilityLabel("Corrected spoken words")
        .overlay(RoundedRectangle(cornerRadius: 8)
          .stroke(Color.secondary.opacity(0.25)))
      if let correctionError = self.correctionError {
        Label(correctionError, systemImage: "exclamationmark.triangle")
          .font(.footnote)
          .foregroundStyle(.red)
      }
      HStack {
        Button("Cancel") { self.cancelCorrection() }
          .buttonStyle(.bordered)
        Spacer()
        Button("Save & Learn") {
          self.correctionFocused = false
          if self.onCorrection(self.correctedDraft) {
            self.correctionError = nil
            self.isEditing = false
          } else {
            self.correctionError = "Unable to save locally. Check shared storage."
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(self.correctedDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      Text("Corrections stay on this iPhone and improve local matching; they do not retrain the speech model.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding(12)
    .background(Color(uiColor: .tertiarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .onAppear { self.correctionFocused = true }
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
    self.correctionFocused = true
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
