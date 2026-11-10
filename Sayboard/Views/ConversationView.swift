import SwiftUI

/// Offline face-to-face translation. The two panels share one microphone
/// capture owner and one text-model coordinator; no simultaneous ASR jobs.
struct ConversationView: View {
  @EnvironmentObject private var speechService: SpeechRecognitionService
  @ObservedObject private var conversation = ConversationCoordinator.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var visitorOutput = VoiceOutputTarget.cantonese
  @State private var myOutput = VoiceOutputTarget.custom
  @State private var visitorCode = "yue"
  @State private var myCode = "tr"
  @State private var showingDiscard = false

  var body: some View {
    GeometryReader { geometry in
      let panelHeight = max(160, (geometry.size.height - 12) / 2)
      VStack(spacing: 12) {
        self.panel(side: .other)
          .frame(height: panelHeight)
          .rotationEffect(.degrees(180))
        self.panel(side: .me)
          .frame(height: panelHeight)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationTitle("Conversation")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button("Save as Meeting", systemImage: "square.and.arrow.down") {
            _ = self.conversation.saveAsMeeting()
          }
          .disabled(self.conversation.turns.isEmpty
            || self.conversation.recordingSide != nil || self.conversation.processing)
          Button("Discard Conversation", systemImage: "trash", role: .destructive) {
            self.showingDiscard = true
          }
          .disabled(self.conversation.turns.isEmpty
            || self.conversation.recordingSide != nil || self.conversation.processing)
        } label: {
          Image(systemName: "ellipsis.circle")
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Conversation options")
      }
    }
    .confirmationDialog(
      "Discard unsaved conversation?",
      isPresented: self.$showingDiscard,
      titleVisibility: .visible
    ) {
      Button("Discard Audio & Transcripts", role: .destructive) {
        self.conversation.discardDraft()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Only the current unsaved conversation draft will be deleted.")
    }
    .safeAreaInset(edge: .bottom) {
      HStack(spacing: 12) {
        Label(self.conversation.status, systemImage: "waveform")
          .font(.caption)
          .lineLimit(2)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Button {
          _ = self.conversation.saveAsMeeting()
        } label: {
          Label("Save as Meeting", systemImage: "square.and.arrow.down")
            .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .disabled(self.conversation.turns.isEmpty
          || self.conversation.recordingSide != nil || self.conversation.processing)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 5)
      .background(.thinMaterial)
    }
  }

  private func panel(side: ConversationSpeaker) -> some View {
    // Each half faces the recipient. Show the opposite speaker's
    // original and translation so a Turkish-speaking visitor sees Turkish
    // above, while the user reads Cantonese below.
    let recent = self.conversation.turns.last(where: { $0.speaker != side })
    let recording = self.conversation.recordingSide == side
    let target = side == .other ? self.myOutput : self.visitorOutput
    let code = side == .other ? self.myCode : self.visitorCode
    let translatedTo = (recent?.targetCode ?? PreferredVoiceLanguages.currentCode(
      target: target, custom: code
    )).uppercased()
    return VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text(side.title)
          .font(.headline)
        Spacer()
        self.targetPicker(side: side == .other ? .me : .other)
      }
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(recording ? "Original · Live" : "Original · ASR")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Spacer()
          if let detected = recent?.detectedLanguageCode {
            Text(detected.uppercased())
              .font(.caption2.monospaced())
              .foregroundStyle(.secondary)
              .accessibilityLabel("Estimated source language: " + detected)
          } else {
            Text("AUTO").font(.caption2.monospaced()).foregroundStyle(.secondary)
          }
        }
        ScrollView {
          Text(recording
            ? (self.conversation.liveSource.isEmpty
              ? "Listening… original words appear after recognition."
              : self.conversation.liveSource)
            : (recent?.sourceText.isEmpty == false
              ? recent!.sourceText
              : "Tap the microphone to record a turn."))
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxHeight: .infinity)
        Divider()
        Text("Translation · " + translatedTo)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.blue)
        ScrollView {
          Text(recent?.translatedText ?? (
            self.conversation.processing ? "Processing offline…" :
              (recent?.sourceText.isEmpty == false ? "Translation not available yet." :
                "Translation will appear here.")
          ))
          .font(.system(size: 28, weight: .medium))
          .foregroundStyle(.blue)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
        }
        .frame(maxHeight: .infinity)
      }
      HStack(spacing: 10) {
        if let recent, recent.needsRetry, !recording, !self.conversation.processing {
          Button("Retry") {
            Task { await self.conversation.retry(recent.id, using: self.speechService) }
          }
          .buttonStyle(.bordered)
          .accessibilityHint("Uses saved audio or source text without recording again")
        }
        Spacer()
        Button {
          if recording {
            Task {
              await self.conversation.stop(using: self.speechService)
            }
          } else {
            self.conversation.start(
              side, using: self.speechService, options: self.output(side: side)
            )
          }
        } label: {
          Label(recording ? "Stop" : "Speak",
                systemImage: recording ? "stop.fill" : "mic.fill")
            .font(.headline)
            .frame(minWidth: 80, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(recording ? .red : .accentColor)
        .disabled(self.conversation.processing ||
          (self.conversation.recordingSide != nil && !recording) ||
          !ConversationTurnPolicy.validOutput(target: target, custom: code))
        .accessibilityLabel(recording ? "Stop " + side.title + " recording"
          : "Record " + side.title + " speaking")
      }
    }
    .padding(14)
    .background(Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .padding(.horizontal, 12)
  }

  @ViewBuilder
  private func targetPicker(side: ConversationSpeaker) -> some View {
    let binding: Binding<VoiceOutputTarget> =
      side == .other ? self.$visitorOutput : self.$myOutput
    Picker("Translate to", selection: binding) {
      Text("YUE").tag(VoiceOutputTarget.cantonese)
      Text("EN").tag(VoiceOutputTarget.english)
      Text("DE").tag(VoiceOutputTarget.german)
      Text("ZH").tag(VoiceOutputTarget.traditionalChinese)
      Text("Other").tag(VoiceOutputTarget.custom)
      Text("Original").tag(VoiceOutputTarget.original)
    }
    .pickerStyle(.menu)
    .disabled(self.conversation.recordingSide != nil || self.conversation.processing)
    if (side == .other ? self.visitorOutput : self.myOutput) == .custom {
      TextField("Language", text: side == .other ? self.$visitorCode : self.$myCode)
        .font(.caption)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .frame(width: 58)
        .accessibilityLabel("Translation target language code")
        .disabled(self.conversation.recordingSide != nil || self.conversation.processing)
    }
  }

  private func output(side: ConversationSpeaker) -> VoiceOutputConfiguration {
    let target = side == .other ? self.visitorOutput : self.myOutput
    let code = side == .other ? self.visitorCode : self.myCode
    return VoiceOutputConfiguration(
      cleanupEnabled: false,
      target: target,
      register: .faithful,
      customLanguage: target == .custom ? code : ""
    )
  }
}
