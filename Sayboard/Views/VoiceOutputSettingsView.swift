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
        Picker("Dictation tone", selection: self.$register) {
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
        Text("Offline Models")
      } footer: {
        Text("Speech recognition uses the selected speech model. Cleanup and translation need an installed offline text model.")
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
        Text("Offline AI can edit a transcript but cannot recover words missing from the recording.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Voice Output & Translation")
    .navigationBarTitleDisplayMode(.inline)

  }
}
