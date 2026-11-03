import SwiftUI

struct VoiceOutputSettingsView: View {
  @EnvironmentObject private var llmDownloadService: LLMDownloadService
  @EnvironmentObject private var speechModels: ModelDownloadService

  @AppStorage(SharedKey.voiceCleanupEnabled, store: AppGroup.sharedDefaults ?? .standard)
  private var cleanupEnabled = false

  @AppStorage(SharedKey.keyboardShowOutputLanguageButton, store: AppGroup.sharedDefaults ?? .standard)
  private var showOutputLanguageButton = true

  @AppStorage(SharedKey.voiceOutputTarget, store: AppGroup.sharedDefaults ?? .standard)
  private var target = VoiceOutputTarget.original.rawValue

  @AppStorage(SharedKey.voiceOutputRegister, store: AppGroup.sharedDefaults ?? .standard)
  private var register = VoiceOutputRegister.faithful.rawValue

  @AppStorage(SharedKey.voiceCustomLanguage, store: AppGroup.sharedDefaults ?? .standard)
  private var customLanguage = ""

  var body: some View {
    Form {
      Section {
        Toggle(isOn: self.$cleanupEnabled) {
          Label("Clean up transcription with offline AI", systemImage: "wand.and.stars")
        }
        Toggle(isOn: self.$showOutputLanguageButton) {
          Label("Show output-language button on keyboard", systemImage: "globe")
        }
        Picker(selection: self.$target) {
          ForEach(VoiceOutputTarget.allCases) { option in
            Text(option.title).tag(option.rawValue)
          }
        } label: {
          Label("Output language", systemImage: "character.bubble")
        }
        if self.target == VoiceOutputTarget.custom.rawValue {
          HStack {
            Label("Language Code", systemImage: "character.cursor.ibeam")
            TextField("fr, es, ja, ko", text: self.$customLanguage)
              .multilineTextAlignment(.trailing)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
          }
          if VoiceOutputTarget.customLanguageName(self.customLanguage) == nil {
            Text("Use a valid language code. An invalid target keeps the original language.")
              .font(.footnote).foregroundStyle(.orange)
          }
        }
        Picker(selection: self.$register) {
          ForEach(VoiceOutputRegister.allCases) { option in
            Text(option.title).tag(option.rawValue)
          }
        } label: {
          Label("Dictation tone", systemImage: "text.alignleft")
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
          LabeledContent {
            Text(self.speechModels.selectedVariant.displayName)
              .foregroundStyle(.secondary)
          } label: {
            Label("Speech recognition model", systemImage: "waveform")
          }
        }
        NavigationLink {
          LLMModelsScreen()
        } label: {
          LabeledContent {
            Text(self.llmDownloadService.hasUsableModel
              ? self.llmDownloadService.selectedVariant.displayName : "Download required")
              .foregroundStyle(.secondary)
          } label: {
            Label("Offline cleanup / translation model", systemImage: "cpu")
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
        Text("Offline AI can edit a transcript but cannot recover words missing from the recording.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Voice Output & Translation")
    .navigationBarTitleDisplayMode(.inline)

  }
}
