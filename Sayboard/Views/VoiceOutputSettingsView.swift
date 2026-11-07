import SwiftUI

/// Dictation transcript output preferences, independent of AI action formatting.
struct VoiceOutputSettingsView: View {
  var inline = false

  @AppStorage(SharedKey.voiceCleanupEnabled, store: AppGroup.sharedDefaults ?? .standard)
  private var cleanupEnabled = false
  @AppStorage(SharedKey.voicePunctuationEnabled, store: AppGroup.sharedDefaults ?? .standard)
  private var punctuationEnabled = true
  @AppStorage(SharedKey.voiceOutputTarget, store: AppGroup.sharedDefaults ?? .standard)
  private var target = VoiceOutputTarget.original.rawValue
  @AppStorage(SharedKey.voiceOutputRegister, store: AppGroup.sharedDefaults ?? .standard)
  private var register = VoiceOutputRegister.faithful.rawValue
  @AppStorage(SharedKey.voiceCustomLanguage, store: AppGroup.sharedDefaults ?? .standard)
  private var customLanguage = ""

  var body: some View {
    Group {
      if self.inline {
        self.controls
      } else {
        Form {
          Section("Output") { self.controls }
        }
        .navigationTitle("Output")
        .navigationBarTitleDisplayMode(.inline)
      }
    }
  }

  private var currentOutputAbbreviation: String {
    (VoiceOutputTarget(rawValue: self.target) ?? .original)
      .abbreviatedLabel(customLanguage: self.customLanguage)
  }

  @ViewBuilder
  private var controls: some View {
    Toggle(isOn: self.$cleanupEnabled) {
      Label("Transcript Cleanup", systemImage: "wand.and.stars")
    }
    HStack {
      Label("Output Language", systemImage: "character.bubble")
      Spacer(minLength: 6)
      Menu {
        ForEach(VoiceOutputTarget.allCases.filter { $0 != .custom }) { option in
          Button {
            self.target = option.rawValue
          } label: {
            Text(LocalizedStringKey(option.title))
            if self.target == option.rawValue { Image(systemName: "checkmark") }
          }
        }
        Divider()
        Button("French") {
          self.customLanguage = "fr"
          self.target = VoiceOutputTarget.custom.rawValue
        }
        Button("Chinese (Simplified)") {
          self.customLanguage = "zh-Hans"
          self.target = VoiceOutputTarget.custom.rawValue
        }
        Button("Other language") {
          self.customLanguage = ""
          self.target = VoiceOutputTarget.custom.rawValue
        }
      } label: {
        HStack(spacing: 5) {
          Text(verbatim: self.currentOutputAbbreviation)
          Image(systemName: "chevron.up.chevron.down").font(.caption2)
        }
        .foregroundStyle(.secondary)
      }
    }
    Toggle(isOn: self.$punctuationEnabled) {
      Label("Include Punctuation", systemImage: "textformat")
    }
    if self.target == VoiceOutputTarget.custom.rawValue
      && !["fr", "zh-Hans"].contains(self.customLanguage) {
      HStack {
        Label("Language Code", systemImage: "character.cursor.ibeam")
        TextField("fr, es, ja, ko", text: self.$customLanguage)
          .multilineTextAlignment(.trailing)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
      }
      if VoiceOutputTarget.customLanguageName(self.customLanguage) == nil {
        Text("Invalid language code")
          .font(.footnote).foregroundStyle(.orange)
      }
    }
    Picker(selection: self.$register) {
      ForEach(VoiceOutputRegister.allCases) { option in
        Text(LocalizedStringKey(option.title)).tag(option.rawValue)
      }
    } label: {
      Label("Tone", systemImage: "text.alignleft")
    }
  }
}
