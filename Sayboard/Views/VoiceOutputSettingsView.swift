import SwiftUI

/// Dictation transcript output preferences, independent of AI action formatting.
struct VoiceOutputSettingsView: View {
  var inline = false

  @AppStorage(SharedKey.voiceCleanupEnabled, store: AppGroup.sharedDefaults ?? .standard)
  private var cleanupEnabled = false
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

  @ViewBuilder
  private var controls: some View {
    Toggle(isOn: self.$cleanupEnabled) {
      Label("Transcript Cleanup", systemImage: "wand.and.stars")
    }
    Picker(selection: self.$target) {
      ForEach(VoiceOutputTarget.allCases) { option in
        Text(option.title).tag(option.rawValue)
      }
    } label: {
      Label("Output Language", systemImage: "character.bubble")
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
        Text("Invalid language code")
          .font(.footnote).foregroundStyle(.orange)
      }
    }
    Picker(selection: self.$register) {
      ForEach(VoiceOutputRegister.allCases) { option in
        Text(option.title).tag(option.rawValue)
      }
    } label: {
      Label("Tone", systemImage: "text.alignleft")
    }
  }
}
