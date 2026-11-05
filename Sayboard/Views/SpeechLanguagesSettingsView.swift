import SwiftUI

/// The single place where users select spoken languages. These preferences
/// also enable the Cantonese candidate bar in the Alphabet keyboard.
struct SpeechLanguagesSettingsView: View {
  var inline = false
  var rowsOnly = false

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
      if self.rowsOnly {
        VStack(alignment: .leading, spacing: 6) { self.languageSelectionRows }
      } else {
        Section {
          self.languageSelectionRows
        } header: {
          Text("Speech & Languages")
        } footer: {
          if !self.inline {
            Text("Cantonese also enables offline Chinese suggestions in Alphabet. Qwen3 voice recognition uses auto-detection.")
          }
        }

      }
    }
    .sheet(isPresented: self.$showPreferredLanguagePicker) {
      LanguagePickerView(
        mode: .ordered(Binding(
          get: { self.spokenLanguages },
          set: { updated in
            let normalized = PreferredVoiceLanguages.normalized(updated)
            if normalized != self.spokenLanguages {
              FeatureDiagnostics.record(.language, .selected)
            }
            self.spokenLanguages = normalized
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
              FeatureDiagnostics.record(.language, .fallback)
              settings.voiceOutputTarget = .original
            }
          }
        )),
        availableLanguages: SpeechLanguages.all,
        titleKey: "Preferred Languages",
        autoDetectKey: "Any language"
      )
    }
    .onAppear {
      self.spokenLanguages = SharedSettings().preferredSpokenLanguages
    }
  }

  @ViewBuilder
  private var languageSelectionRows: some View {
    Button {
      self.showPreferredLanguagePicker = true
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        Label("Language Priority", systemImage: "globe")
        Text(self.spokenLanguages.isEmpty
          ? "Any language"
          : self.spokenLanguages.enumerated().map {
              "\($0.offset + 1). " + ($0.element == "zh" ? String(localized: "Mandarin")
                : self.locale.capitalizedLanguageName(forLanguageCode: $0.element))
            }.joined(separator: " · "))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.leading)
          .lineLimit(2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    if !self.unsupportedSpokenLanguages.isEmpty {
      Label(
        "The selected speech model may not recognize: \(self.unsupportedSpokenLanguages.joined(separator: ", "))",
        systemImage: "exclamationmark.triangle"
      )
      .font(.footnote)
      .foregroundStyle(.orange)
    }
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

