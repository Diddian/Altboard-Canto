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
        self.languageSelectionRows
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
            // Recognition preferences must not reset a separately selected
            // translation output language.
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
      HStack(spacing: 10) {
        Image(systemName: "globe")
          .font(.system(size: 18, weight: .regular))
          .frame(width: 24)
          .foregroundStyle(Color.accentColor)
          .accessibilityHidden(true)
        Text("Language Priority")
          .foregroundStyle(.primary)
        Spacer(minLength: 8)
        Text(verbatim: self.languagePrioritySummary)
          .font(.body.weight(.semibold))
          .foregroundStyle(Color.accentColor)
          .lineLimit(1)
          .truncationMode(.middle)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Color.accentColor)
      }
      .contentShape(Rectangle())
      .frame(height: 31)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Language Priority")
    .accessibilityValue(self.languagePriorityAccessibilityValue)
    .accessibilityHint("Open language priority editor to add, remove or reorder languages")
    if !self.unsupportedSpokenLanguages.isEmpty {
      Label(
        "Some preferred languages may not be supported by the selected speech model.",
        systemImage: "exclamationmark.triangle"
      )
      .font(.footnote)
      .foregroundStyle(.orange)
    }
  }

  private var languagePrioritySummary: String {
    let codes = PreferredVoiceLanguages.normalized(self.spokenLanguages)
    return codes.first.map { PreferredVoiceLanguages.shortLabel(for: $0) } ?? "AUTO"
  }

  private var languagePriorityAccessibilityValue: String {
    self.spokenLanguages.isEmpty ? "Any language" :
      self.spokenLanguages.map { self.displayName(for: $0) }.joined(separator: ", ")
  }

  @EnvironmentObject private var speechModels: ModelDownloadService
  @State private var spokenLanguages = SharedSettings().preferredSpokenLanguages
  @State private var showPreferredLanguagePicker = false
  @Environment(\.locale) private var locale

  private func displayName(for code: String) -> String {
    SpeechLanguageNames.name(for: code, locale: self.locale)
  }

  private var unsupportedSpokenLanguages: [String] {
    self.spokenLanguages.filter { !self.speechModels.selectedVariant.supportedLanguages.contains($0) }
      .map { self.displayName(for: $0) }
  }
}

