import SwiftUI

struct VoiceOutputSettingsView: View {
  @EnvironmentObject private var llmDownloadService: LLMDownloadService
  @EnvironmentObject private var speechModels: ModelDownloadService

  @AppStorage(SharedKey.voiceCleanupEnabled, store: AppGroup.sharedDefaults ?? .standard)
  private var cleanupEnabled = false

  @AppStorage(SharedKey.voiceOutputTarget, store: AppGroup.sharedDefaults ?? .standard)
  private var target = VoiceOutputTarget.original.rawValue

  @AppStorage(SharedKey.voiceOutputRegister, store: AppGroup.sharedDefaults ?? .standard)
  private var register = VoiceOutputRegister.faithful.rawValue

  @AppStorage(SharedKey.voiceCustomLanguage, store: AppGroup.sharedDefaults ?? .standard)
  private var customLanguage = ""
  @State private var spokenLanguages = SharedSettings().preferredSpokenLanguages
  @State private var showPreferredLanguagePicker = false
  @Environment(\.locale) private var locale

  private var unsupportedSpokenLanguages: [String] {
    self.spokenLanguages.filter { !self.speechModels.selectedVariant.supportedLanguages.contains($0) }
      .map { self.locale.capitalizedLanguageName(forLanguageCode: $0) }
  }

  var body: some View {
    Form {
      Section {
        Button {
          self.showPreferredLanguagePicker = true
        } label: {
          LabeledContent("Languages I speak") {
            Text(self.spokenLanguages.isEmpty
              ? "Any language"
              : self.spokenLanguages.map { self.locale.capitalizedLanguageName(forLanguageCode: $0) }
                .joined(separator: ", "))
              .multilineTextAlignment(.trailing)
              .lineLimit(2)
          }
        }
        if !self.unsupportedSpokenLanguages.isEmpty {
          Label(
            "The selected speech model may not recognize: \(self.unsupportedSpokenLanguages.joined(separator: ", "))",
            systemImage: "exclamationmark.triangle"
          )
          .font(.footnote)
          .foregroundStyle(.orange)
        }
      } header: {
        Text("Preferred Languages")
      } footer: {
        Text("Your keyboard cycles AUTO plus these languages. Whisper can lock a single language. Qwen3 only supports auto-detection here; an unexpected script is blocked rather than inserted.")
      }

      Section {
        Toggle("Clean up transcription with offline AI", isOn: self.$cleanupEnabled)
        Picker("Output language", selection: self.$target) {
          ForEach(VoiceOutputTarget.allCases) { option in
            Text(option.title).tag(option.rawValue)
          }
        }
        if self.target == VoiceOutputTarget.custom.rawValue {
          TextField("Language code, e.g. fr, es, ja, ko", text: self.$customLanguage)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          if VoiceOutputTarget.customLanguageName(self.customLanguage) == nil {
            Text("Use a valid language code. An invalid target keeps the original language.")
              .font(.footnote).foregroundStyle(.orange)
          }
        }
        Picker("Writing style", selection: self.$register) {
          ForEach(VoiceOutputRegister.allCases) { option in
            Text(option.title).tag(option.rawValue)
          }
        }
      } header: {
        Text("Dictation → Edit → Output")
      } footer: {
        Text("Original keeps the language you spoke, including Cantonese-English-German mixing. As spoken preserves your tone; Casual and Formal change only the register.")
      }

      Section {
        NavigationLink {
          ModelsView()
        } label: {
          LabeledContent("Speech recognition model") {
            Text(self.speechModels.selectedVariant.displayName)
              .foregroundStyle(.secondary)
          }
        }
        NavigationLink {
          LLMModelsScreen()
        } label: {
          LabeledContent("Offline cleanup / translation model") {
            Text(self.llmDownloadService.hasUsableModel
              ? self.llmDownloadService.selectedVariant.displayName : "Download required")
              .foregroundStyle(.secondary)
          }
        }
        if !self.llmDownloadService.hasUsableModel {
          Label(
            "Without a downloaded text model, translation and AI corrections are unavailable. An explicit translation failure leaves the original in history instead of inserting it in the wrong language.",
            systemImage: "exclamationmark.triangle"
          )
          .font(.footnote).foregroundStyle(.orange)
        }
      } header: {
        Text("On-device LLM")
      } footer: {
        Text("The keyboard language key cycles AUTO and your preferred languages. Translation runs locally, when a text model is installed.")
      }

      Section {
        NavigationLink {
          CantoneseCorrectionsView()
        } label: {
          Label("Cantonese word corrections", systemImage: "text.badge.checkmark")
        }
      } header: {
        Text("Personal Dictionary")
      } footer: {
        Text("Add exact phrases the speech recognizer often mishears. These corrections run offline before any optional AI cleanup and do not retrain the speech model.")
      }

      Section {
        Text("ASR detects spoken languages where supported. An LLM edits the transcript, not the original audio. It can correct likely errors but cannot recover words it never heard.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Voice Output")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: self.$showPreferredLanguagePicker) {
      LanguagePickerView(
        mode: .multi(Binding(
          get: { Set(self.spokenLanguages) },
          set: { updated in
            let kept = self.spokenLanguages.filter { updated.contains($0) }
            self.spokenLanguages = kept + updated.subtracting(kept).sorted()
            let settings = SharedSettings()
            settings.preferredSpokenLanguages = self.spokenLanguages
            settings.setPreferredLanguages(
              SpeechModelRecommendation.preferredLanguages(
                for: settings.selectedVariant, from: self.spokenLanguages
              ),
              for: settings.selectedVariant
            )
            let old = PreferredVoiceLanguages.currentCode(
              target: settings.voiceOutputTarget, custom: settings.voiceCustomLanguage
            )
            if !old.isEmpty && !self.spokenLanguages.contains(old) {
              settings.voiceOutputTarget = .original
            }
          }
        )),
        availableLanguages: SpeechLanguages.all,
        titleKey: "Preferred Languages",
        autoDetectKey: "Any language"
      )
    }
    .onAppear { self.spokenLanguages = SharedSettings().preferredSpokenLanguages }
  }
}
