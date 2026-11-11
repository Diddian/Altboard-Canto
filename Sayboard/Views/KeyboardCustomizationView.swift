import SwiftUI

/// One place for optional keyboard behaviors, separate from layout selection.
struct KeyboardCustomizationView: View {
  var inline = false
  @AppStorage(SharedKey.keyboardShowGlobeKey, store: AppGroup.sharedDefaults ?? .standard)
  private var showGlobe = false
  @AppStorage(SharedKey.keyboardShowSettingsKey, store: AppGroup.sharedDefaults ?? .standard)
  private var showSettingsKey = true
  @AppStorage(SharedKey.keyboardShowOutputLanguageButton, store: AppGroup.sharedDefaults ?? .standard)
  private var showOutputButton = true
  @AppStorage(SharedKey.keyboardShowAIButton, store: AppGroup.sharedDefaults ?? .standard)
  private var showAIButton = true

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
    Toggle("Extra Globe Key", isOn: self.$showGlobe)
      .accessibilityHint("Optional keyboard switch at the far left of the action row")
    Toggle("Settings Key", isOn: self.$showSettingsKey)
    Toggle("Output Key", isOn: self.$showOutputButton)
    Toggle("AI Key", isOn: self.$showAIButton)
  }

}
