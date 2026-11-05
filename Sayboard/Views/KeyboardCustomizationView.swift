import SwiftUI

/// One place for optional keyboard behaviors, separate from layout selection.
struct KeyboardCustomizationView: View {
  var inline = false
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

  var body: some View {
    Group {
      if self.inline {
        self.sections
      } else {
        Form { self.sections }
          .navigationTitle("Keyboard Options")
          .navigationBarTitleDisplayMode(.inline)
      }
    }
  }

  @ViewBuilder
  private var sections: some View {
    Section("Typing") {
      Toggle("Auto-capitalization", isOn: self.$autoCapitalize)
      Toggle("Double-Space Period", isOn: self.$periodShortcut)
    }

    Section {
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
    } header: {
      Text("Haptic Feedback")
    } footer: {
      Text("iOS does not expose the exact native keyboard vibration strength. Reset restores Altboard's default.")
    }

    Section {
      Toggle("Extra Globe Key", isOn: self.$showGlobe)
      Toggle("Settings Key", isOn: self.$showSettingsKey)
      Toggle("Output Key", isOn: self.$showOutputButton)
      Toggle("AI Key", isOn: self.$showAIButton)
        .disabled(!self.aiEnabled)
    } header: {
      Text("Keyboard Buttons")
    } footer: {
      Text("iOS may require the Globe key. AI requires an installed text model.")
    }
  }
}
