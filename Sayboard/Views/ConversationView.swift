import SwiftUI
import NaturalLanguage

/// Face-to-face subtitles: both parties see live source, then each sees
/// the result intended for them. The speaker sees the cleaned original;
/// the listener sees only the translated text.
struct ConversationView: View {
  @EnvironmentObject private var speechService: SpeechRecognitionService
  @ObservedObject private var conversation = ConversationCoordinator.shared
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var visitorOutput = VoiceOutputTarget.german
  @State private var myOutput = VoiceOutputTarget.cantonese
  @State private var visitorCode = "de"
  @State private var myCode = "yue"
  @State private var showingDiscard = false

  private var liveLanguage: String? {
    let text = self.conversation.liveSource
    guard text.count >= 12 else { return nil }
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    return recognizer.dominantLanguage?.rawValue
  }

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
  }

  private func panel(side: ConversationSpeaker) -> some View {
    let activeSpeaker = self.conversation.recordingSide
    let isSpeaking = activeSpeaker == side
    let live = activeSpeaker != nil
    let recent = self.conversation.turns.last
    let speakerOwnsLastTurn = recent?.speaker == side
    let showsOriginalLanguage = speakerOwnsLastTurn || recent?.targetCode == ""
    let target = side == .other ? self.visitorOutput : self.myOutput
    let code = side == .other ? self.visitorCode : self.myCode
    let targetCode = PreferredVoiceLanguages.currentCode(target: target, custom: code)
    let detected = live ? self.liveLanguage : recent?.detectedLanguageCode
    let displayText: String
    if live {
      displayText = self.conversation.liveSource.isEmpty
        ? "Listening…" : self.conversation.liveSource
    } else if let recent {
      if showsOriginalLanguage {
        let source = recent.cleanedSourceText ?? recent.sourceText
        displayText = source.isEmpty ? "Recognizing speech…" : source
      } else {
        displayText = recent.translatedText ?? (
          self.conversation.processing ? "Preparing translation…" :
            "Translation unavailable. Retry the saved turn."
        )
      }
    } else {
      displayText = "Tap the microphone to begin."
    }

    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Text(side.title).font(.headline)
        Spacer(minLength: 8)
        if let detected, !detected.isEmpty {
          Text(detected.uppercased())
            .font(.caption.monospaced().weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel("Detected language: " + detected)
        }
        self.targetPicker(side: side)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          Text(live ? "Live Transcription" :
            (showsOriginalLanguage ? "Transcript" :
              "Translation · " + PreferredVoiceLanguages.outputShortLabel(
                for: recent?.targetCode ?? targetCode
              )))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(displayText)
            .font(.system(size: 25, weight: .regular))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      if !self.conversation.status.isEmpty {
        Text(self.conversation.status)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .center)
      }
      HStack {
        if let recent, recent.needsRetry, !live, !self.conversation.processing,
           !speakerOwnsLastTurn {
          Button("Retry") {
            Task { await self.conversation.retry(recent.id, using: self.speechService) }
          }
          .buttonStyle(.bordered)
        }
        Spacer(minLength: 0)
        self.recordButton(side: side, recording: isSpeaking, target: target, code: code)
        Spacer(minLength: 0)
      }
    }
    .padding(14)
    .background(Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .padding(.horizontal, 12)
  }

  private func recordButton(
    side: ConversationSpeaker, recording: Bool,
    target: VoiceOutputTarget, code: String
  ) -> some View {
    Button {
      if recording {
        Task { await self.conversation.stop(using: self.speechService) }
      } else {
        self.conversation.start(side, using: self.speechService,
          options: self.output(for: side))
      }
    } label: {
      ZStack {
        Circle()
          .fill(Color(uiColor: .tertiarySystemBackground))
          .frame(width: 70, height: 70)
        Circle()
          .fill(Color.red)
          .frame(width: 58, height: 58)
        if recording {
          RoundedRectangle(cornerRadius: 5)
            .fill(.white)
            .frame(width: 22, height: 22)
        }
      }
    }
    .buttonStyle(.plain)
    .disabled(self.conversation.processing ||
      (self.conversation.recordingSide != nil && !recording) ||
      !ConversationTurnPolicy.validOutput(
        target: self.output(for: side).target,
        custom: self.output(for: side).customLanguage
      ))
    .accessibilityLabel(recording ? "Stop " + side.title + " recording"
      : "Record " + side.title + " speaking")
  }

  @ViewBuilder
  private func targetPicker(side: ConversationSpeaker) -> some View {
    let binding: Binding<VoiceOutputTarget> =
      side == .other ? self.$visitorOutput : self.$myOutput
    Picker("Translate to", selection: binding) {
      Text("粵").tag(VoiceOutputTarget.cantonese)
      Text("EN").tag(VoiceOutputTarget.english)
      Text("DE").tag(VoiceOutputTarget.german)
      Text("繁").tag(VoiceOutputTarget.traditionalChinese)
      Text("Other").tag(VoiceOutputTarget.custom)
      Text("Original Language").tag(VoiceOutputTarget.original)
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

  /// The requested output belongs to the person listening, never the speaker.
  private func output(for speaker: ConversationSpeaker) -> VoiceOutputConfiguration {
    let target = speaker == .me ? self.visitorOutput : self.myOutput
    let code = speaker == .me ? self.visitorCode : self.myCode
    return VoiceOutputConfiguration(
      cleanupEnabled: true,
      target: target,
      register: .faithful,
      customLanguage: target == .custom ? code : ""
    )
  }
}
