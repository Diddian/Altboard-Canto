import SwiftUI

/// Replaces the original toolbar, never covers live gear/output/microphone
/// controls. All inputs are available immediately on press; LLM work starts
/// only after a user explicitly chooses an action.
struct KeyboardLLMActionsToolbar: View {
  let proxy: KeyboardProxy
  @ObservedObject var keyboardState: KeyboardState

  var body: some View {
    HStack(spacing: KeyboardChromeMetrics.buttonSpacing) {
      if self.keyboardState.showGlobeKey ||
          (self.keyboardState.effectiveTypingKind == .alphabetic
            && self.keyboardState.needsInputModeSwitchKey) {
        NativeInputModeSwitchKey(
          configure: self.keyboardState.configureInputModeListButton,
          iconName: "globe"
        )
        .frame(width: KeyboardChromeMetrics(keyboardState: self.keyboardState).sideButtonWidth,
               height: KeyboardChromeMetrics.keyHeight)
      }
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
        onRecoverResult: {
          self.keyboardState.showLLMActions = false
          self.proxy.copyRecoverableLLMResult()
        },
        keyboardState: self.keyboardState
      )
      .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity)
    .frame(height: KeyboardChromeMetrics.keyHeight)
    .background(Color(uiColor: KeyboardPalette.backdrop))
  }
}
