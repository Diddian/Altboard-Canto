import SwiftUI

struct ComposePresetBar: View {
  @ObservedObject var keyboardState: KeyboardState

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(VoiceComposePreset.allCases) { preset in
          Button {
            self.keyboardState.selectComposePreset(preset)
          } label: {
            Text(preset.label)
              .font(.system(size: 12.kbScaled, weight: self.keyboardState.composePreset == preset ? .semibold : .regular))
              .foregroundStyle(self.keyboardState.composePreset == preset ? Color.accentColor : Color.primary)
              .padding(.horizontal, 10.kbScaled)
              .frame(height: 29.kbScaled)
              .background {
                Capsule().fill(self.keyboardState.composePreset == preset
                  ? Color.accentColor.opacity(0.16) : Color(.keyBackground))
              }
          }
          .buttonStyle(.plain)
          .disabled(self.keyboardState.isRecording || self.keyboardState.isProcessing)
        }
      }
      .padding(.horizontal, 5)
    }
    .frame(height: KeyboardMetrics.composePresetBarHeight.kbScaled)
    .accessibilityLabel("Voice Compose writing style presets")
  }
}
