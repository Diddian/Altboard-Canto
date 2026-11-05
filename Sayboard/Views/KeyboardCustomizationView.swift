import SwiftUI

/// One place for optional keyboard behaviors, separate from layout selection.
struct KeyboardCustomizationView: View {
  var inline = false
  @AppStorage(SharedKey.keyboardHapticsEnabled, store: AppGroup.sharedDefaults ?? .standard)
  private var hapticsEnabled = true
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
        self.rows
      } else {
        Form { self.rows }
          .navigationTitle("Keyboard Options")
          .navigationBarTitleDisplayMode(.inline)
      }
    }
  }

  @ViewBuilder
  private var rows: some View {
    Toggle("Auto-capitalization", isOn: self.$autoCapitalize)
    Toggle("Double-Space Period", isOn: self.$periodShortcut)
    Toggle("Haptic Feedback", isOn: self.$hapticsEnabled)
    Toggle("Extra Globe Key", isOn: SharedSettings.keyboardGlobeTemporarilyDisabled
           ? .constant(false) : self.$showGlobe)
      .disabled(SharedSettings.keyboardGlobeTemporarilyDisabled)
    Toggle("Settings Key", isOn: self.$showSettingsKey)
    Toggle("Output Key", isOn: self.$showOutputButton)
    Toggle("AI Key", isOn: self.$showAIButton).disabled(!self.aiEnabled)
  }

}
