import SwiftUI

struct VoiceOutputSettingsView: View {
  @EnvironmentObject private var llmDownloadService: LLMDownloadService
  @EnvironmentObject private var speechModels: ModelDownloadService

  @AppStorage(SharedKey.voiceCleanupEnabled, store: AppGroup.sharedDefaults ?? .standard)
  private var cleanupEnabled = true

  @AppStorage(SharedKey.voiceOutputTarget, store: AppGroup.sharedDefaults ?? .standard)
  private var target = VoiceOutputTarget.original.rawValue

  @AppStorage(SharedKey.voiceOutputRegister, store: AppGroup.sharedDefaults ?? .standard)
  private var register = VoiceOutputRegister.faithful.rawValue

  @AppStorage(SharedKey.voiceCustomLanguage, store: AppGroup.sharedDefaults ?? .standard)
  private var customLanguage = ""

  var body: some View {
    Form {
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
            "Without a downloaded text model, Altboard returns the raw transcription. Translation and AI corrections require a separate LLM.",
            systemImage: "exclamationmark.triangle"
          )
          .font(.footnote).foregroundStyle(.orange)
        }
      } header: {
        Text("On-device LLM")
      } footer: {
        Text("The keyboard language key cycles AUTO → 粵 → EN → DE. More languages are available here. No text is sent to a cloud API.")
      }

      Section {
        Text("ASR detects spoken languages where supported. An LLM edits the transcript, not the original audio. It can correct likely errors but cannot recover words it never heard.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Voice Output")
    .navigationBarTitleDisplayMode(.inline)
  }
}
