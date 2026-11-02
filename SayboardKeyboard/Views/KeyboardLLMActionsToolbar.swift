import SwiftUI

/// Replaces the original toolbar, never covers live gear/output/microphone
/// controls. All inputs are available immediately on press; LLM work starts
/// only after a user explicitly chooses an action.
struct KeyboardLLMActionsToolbar: View {
  let proxy: KeyboardProxy
  @ObservedObject var keyboardState: KeyboardState

  var body: some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      KeyButton(content: .systemImage("xmark"),
                fixedWidth: 32.kbScaled) {
        self.keyboardState.showLLMActions = false
      }
      .accessibilityLabel("Close AI actions")

      LLMActionBar(
        onSelectAction: { action, customId in
          self.keyboardState.showLLMActions = false
          self.proxy.requestLLMProcessing(action, customId)
        },
        keyboardState: self.keyboardState
      )
      .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity, height: KeyboardChromeMetrics.keyHeight)
    .background(Color(uiColor: KeyboardPalette.backdrop))
  }
}
