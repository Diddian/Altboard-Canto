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
  @State private var cleanupEnabled = true

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
          Toggle("Clean Up Speech After Recording", isOn: self.$cleanupEnabled)
            .disabled(self.conversation.recordingSide != nil || self.conversation.processing)
          if let last = self.conversation.turns.last, last.needsRetry {
            Button("Retry Last Turn", systemImage: "arrow.clockwise") {
              Task { await self.conversation.retry(last.id, using: self.speechService) }
            }.disabled(self.conversation.processing || self.conversation.recordingSide != nil)
          }
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
    let detected = live ? self.liveLanguage : recent?.detectedLanguageCode
    let isReceiver = recent != nil && !speakerOwnsLastTurn
    let isTranslating = !live && isReceiver && !showsOriginalLanguage
    let displayText: String
    if live {
      displayText = self.conversation.liveSource.isEmpty
        ? self.localeText(self.conversation.livePreviewUnavailable ? "liveUnavailable" : "listening", target: target)
        : self.visibleSource(self.conversation.liveSource, spokenBy: activeSpeaker ?? side)
    } else if let recent {
      if showsOriginalLanguage {
        let source = recent.cleanedSourceText ?? recent.sourceText
        displayText = source.isEmpty ? self.localeText("recognizing", target: target) :
          self.visibleSource(source, spokenBy: recent.speaker)
      } else {
        displayText = recent.translatedText ?? (
          self.conversation.processing ? self.localeText("preparing", target: target) :
            self.localeText("unavailable", target: target)
        )
      }
    } else {
      displayText = self.localeText("tap", target: target)
    }

    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Text(self.localeText(side == .other ? "other" : "you", target: target))
          .font(.headline)
        Spacer(minLength: 8)
        if let detected, !detected.isEmpty {
          Text(self.nativeLanguageName(detected))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityLabel(self.localeText("detected", target: target) + ": " + self.nativeLanguageName(detected))
        }
        if isTranslating {
          Image(systemName: "arrow.left.arrow.right")
            .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
        }
        self.targetPicker(side: side)
      }

      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          Text(self.localeText(live ? "live" :
            (showsOriginalLanguage ? "transcript" : "translation"), target: target))
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

      if live && self.conversation.livePreviewUnavailable {
        Text(self.localeText("afterStop", target: target))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .center)
      } else if let recent, isReceiver, recent.status == .translationFailed {
        Text(self.localeText("unavailable", target: target))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .center)
      }
      HStack {
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

  private func visibleSource(_ source: String, spokenBy speaker: ConversationSpeaker) -> String {
    // Both sides display the same live source. Cantonese script conversion is
    // display-only, and never alters the saved or detected original transcript.
    let selected = speaker == .other ? self.visitorOutput : self.myOutput
    return selected == .cantonese ? CantoneseOutput.normalize(source) : source
  }

  private func nativeLanguageName(_ code: String) -> String {
    if code.isEmpty { return "Auto" }
    let normalized = code.lowercased()
    if normalized == "yue" { return "粵語" }
    if normalized == "zh-hans" { return "简体中文" }
    if normalized == "zh" { return "中文" }
    if normalized == "zh-hant" { return "繁體中文" }
    let locale = Locale(identifier: normalized)
    return locale.localizedString(forLanguageCode: normalized)
      ?? Locale(identifier: "en").localizedString(forLanguageCode: normalized)
      ?? normalized.uppercased()
  }

  private func localeText(_ key: String, target: VoiceOutputTarget) -> String {
    let language = target == .custom ?
      (self.visitorOutput == .custom ? self.visitorCode : self.myCode) : ""
    let code = switch target {
      case .cantonese: "yue"
      case .traditionalChinese: "zh"
      case .german: "de"
      case .english, .original: "en"
      case .custom: language
    }
    switch code {
    case "yue", "zh":
      switch key {
      case "other": return "對方"
      case "you": return "我"
      case "original": return "原文"
      case "live": return "即時語音轉文字"
      case "transcript": return "逐字稿"
      case "translation": return "翻譯"
      case "listening": return "錄音中，等候第一段文字…"
      case "liveUnavailable": return "錄音中，暫時未能即時辨識"
      case "recognizing": return "正在辨識語音…"
      case "preparing": return "正在翻譯…"
      case "unavailable": return "暫時譯唔到，可以撳重試。"
      case "tap": return "撳咪高峰開始錄音"
      case "detected": return "辨識語言"
      case "afterStop": return "錄音仍會保存；停止後產生逐字稿。"
      case "cleanupHint": return self.cleanupEnabled ? "錄音後會整理逐字稿。" : "錄音後唔會整理原文。"
      case "ready": return "翻譯完成"
      case "pending": return "處理中…"
      case "retry": return "重試"
      default: return key
      }
    case "de":
      switch key {
      case "other": return "Gegenüber"
      case "you": return "Ich"
      case "original": return "Originalsprache"
      case "live": return "Live-Transkription"
      case "transcript": return "Transkript"
      case "translation": return "Übersetzung"
      case "listening": return "Aufnahme läuft. Warte auf den ersten Text…"
      case "liveUnavailable": return "Aufnahme läuft. Live-Text nicht verfügbar."
      case "recognizing": return "Sprache wird erkannt…"
      case "preparing": return "Übersetzung wird vorbereitet…"
      case "unavailable": return "Übersetzung nicht verfügbar. Erneut versuchen."
      case "tap": return "Zum Starten auf das Mikrofon tippen."
      case "detected": return "Erkannte Sprache"
      case "afterStop": return "Audio bleibt gespeichert. Transkript nach Stopp."
      case "cleanupHint": return self.cleanupEnabled ? "Transkript wird nach der Aufnahme bereinigt." : "Keine Textkorrektur nach der Aufnahme."
      case "ready": return "Übersetzung bereit"
      case "pending": return "Wird verarbeitet…"
      case "retry": return "Erneut"
      default: return key
      }
    default:
      switch key {
      case "other": return "Other person"
      case "you": return "You"
      case "original": return "Original Language"
      case "live": return "Live Transcription"
      case "transcript": return "Transcript"
      case "translation": return "Translation"
      case "listening": return "Recording · waiting for first words…"
      case "liveUnavailable": return "Recording · live text unavailable"
      case "recognizing": return "Recognizing speech…"
      case "preparing": return "Preparing translation…"
      case "unavailable": return "Translation unavailable. Retry the saved turn."
      case "tap": return "Tap the microphone to begin."
      case "detected": return "Detected language"
      case "afterStop": return "Audio is saved; transcript will appear after Stop."
      case "cleanupHint": return self.cleanupEnabled ? "Transcript will be cleaned up after recording." : "Transcript cleanup is off."
      case "ready": return "Translation ready"
      case "pending": return "Processing…"
      case "retry": return "Retry"
      default: return key
      }
    }
  }

  /// The requested output belongs to the person listening, never the speaker.
  private func output(for speaker: ConversationSpeaker) -> VoiceOutputConfiguration {
    let target = speaker == .me ? self.visitorOutput : self.myOutput
    let code = speaker == .me ? self.visitorCode : self.myCode
    return VoiceOutputConfiguration(
      cleanupEnabled: self.cleanupEnabled,
      target: target,
      register: .faithful,
      customLanguage: target == .custom ? code : ""
    )
  }
}

