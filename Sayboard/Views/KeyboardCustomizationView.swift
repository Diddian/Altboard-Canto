import SwiftUI

/// One place for optional keyboard behaviors, separate from layout selection.
struct KeyboardCustomizationView: View {
  var inline = false
  // The parent Settings view owns the persisted toggles. Share its live bindings
  // with the preview instead of creating a second AppStorage observer.
  @Binding var showGlobe: Bool
  @Binding var showSettingsKey: Bool
  @Binding var showOutputButton: Bool
  @Binding var showAIButton: Bool

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
