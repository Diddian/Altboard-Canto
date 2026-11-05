import SwiftUI

/// One place for optional keyboard behaviors, separate from layout selection.
struct KeyboardCustomizationView: View {
  @AppStorage(SharedKey.keyboardHapticsEnabled, store: AppGroup.sharedDefaults ?? .standard)
  private var hapticsEnabled = true
  @AppStorage(SharedKey.keyboardHapticStrength, store: AppGroup.sharedDefaults ?? .standard)
  private var hapticStrength = SharedSettings.defaultKeyboardHapticStrength
  @AppStorage(SharedKey.keyboardAutoCapitalizationEnabled, store: AppGroup.sharedDefaults ?? .standard)
  private var autoCapitalize = true
  @AppStorage(SharedKey.periodShortcutEnabled, store: AppGroup.sharedDefaults ?? .standard)
  private var periodShortcut = true
  @AppStorage(SharedKey.keyboardShowGlobeKey, store: AppGroup.sharedDefaults ?? .standard)
  private var showGlobe = false
  @AppStorage(SharedKey.keyboardShowSettingsKey, store: AppGroup.sharedDefaults ?? .standard)
  private var showSettingsKey = true
  @AppStorage(SharedKey.keyboardShowOutputLanguageButton, store: AppGroup.sharedDefaults ?? .standard)
  private var showOutputButton = true
  @AppStorage(SharedKey.keyboardShowAIButton, store: AppGroup.sharedDefaults ?? .standard)
  private var showAIButton = true
  @AppStorage(SharedKey.llmEnabled, store: AppGroup.sharedDefaults ?? .standard)
  private var aiEnabled = false
  @AppStorage(SharedKey.voiceCleanupEnabled, store: AppGroup.sharedDefaults ?? .standard)
  private var voiceCleanup = false
  @AppStorage(SharedKey.voiceOutputTarget, store: AppGroup.sharedDefaults ?? .standard)
  private var outputTarget = VoiceOutputTarget.original.rawValue

  var body: some View {
    Form {
      Section("Typing") {
        Toggle("Auto-capitalize Sentences", isOn: self.$autoCapitalize)
        Toggle("Double-Space Period", isOn: self.$periodShortcut)
        LabeledContent("Autocorrect") {
          Text("Not yet available").foregroundStyle(.secondary)
        }
      }

      Section("Haptic Feedback") {
        Toggle("Haptic Feedback", isOn: self.$hapticsEnabled)
        if self.hapticsEnabled {
          HStack {
            Text("Strength")
            Slider(value: self.$hapticStrength, in: 0.15...1.0)
            Button("Reset") {
              self.hapticStrength = SharedSettings.defaultKeyboardHapticStrength
            }
            .font(.caption)
          }
        }
      } footer: {
        Text("iOS does not expose the exact native keyboard vibration strength. Reset restores Altboard's default.")
      }

      Section("Keyboard Buttons") {
        Toggle("Extra Globe Key", isOn: self.$showGlobe)
        Toggle("Settings Key", isOn: self.$showSettingsKey)
        Toggle("Output & Translation Key", isOn: self.$showOutputButton)
          .disabled(!self.voiceCleanup && self.outputTarget == VoiceOutputTarget.original.rawValue)
        Toggle("Text AI Key", isOn: self.$showAIButton)
          .disabled(!self.aiEnabled)
      } footer: {
        Text("The extra Globe key is optional, but iOS can require a system keyboard switch key. Output and AI keys also depend on their features being enabled.")
      }

      Section("Feature Settings") {
        NavigationLink("Speech Cleanup & Translation") {
          VoiceOutputSettingsView()
        }
        NavigationLink("Text Cleanup & AI Actions") {
          LLMSettingsView()
        }
      }
    }
    .navigationTitle("Customization")
    .navigationBarTitleDisplayMode(.inline)
  }
}
