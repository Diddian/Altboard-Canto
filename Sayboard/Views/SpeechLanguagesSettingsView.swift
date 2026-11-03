import SwiftUI

/// The single place where users select spoken languages. These preferences
/// also enable the Cantonese candidate bar in the Alphabet keyboard.
struct SpeechLanguagesSettingsView: View {
  var inline = false

  var body: some View {
    Group {
      if self.inline {
        self.sections
      } else {
        Form { self.sections }
          .navigationTitle("Speech & Languages")
          .navigationBarTitleDisplayMode(.inline)
      }
    }
  }

  @ViewBuilder
  var sections: some View {
    Group {
      Section {
        Button {
          self.showPreferredLanguagePicker = true
        } label: {
          LabeledContent("Languages I Speak") {
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
        Text("Speech & Languages")
      } footer: {
        Text("Cantonese also enables offline Chinese suggestions in Alphabet. Qwen3 voice recognition uses auto-detection.")
      }

      Section {
        NavigationLink {
          VoiceOutputSettingsView()
        } label: {
          Label("Voice Output & Translation", systemImage: "waveform")
        }
      } footer: {
        Text("Choose the output language, cleanup, dictation tone, and Cantonese corrections.")
      }

      Section("Offline Speech Model") {
        NavigationLink {
          ModelsView()
        } label: {
          LabeledContent("Speech Recognition") {
            Text(self.speechModels.selectedVariant.displayName)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
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

  @EnvironmentObject private var speechModels: ModelDownloadService
  @State private var spokenLanguages = SharedSettings().preferredSpokenLanguages
  @State private var showPreferredLanguagePicker = false
  @Environment(\.locale) private var locale

  private var unsupportedSpokenLanguages: [String] {
    self.spokenLanguages.filter { !self.speechModels.selectedVariant.supportedLanguages.contains($0) }
      .map { self.locale.capitalizedLanguageName(forLanguageCode: $0) }
  }
}
